# UE PBR Energy Conservation System — Deep Dive

## Problem Statement

### Multi-Scattering Energy Loss
Standard GGX BRDF only models single scattering. White material (albedo=1) at high roughness appears grey — up to 40% energy loss at roughness=1. This is revealed by the **Furnace Test**: white sphere in uniform white environment should reflect 100% but GGX returns ~60%.

### Diffuse-Specular Energy Competition
Diffuse and Specular share the same incoming light. Without correction, their combined energy can exceed 1.0.

### Multi-Layer Transmission
ClearCoat (two-layer BRDF) requires tracking energy reflection/absorption at the top layer and only passing the remainder to the bottom layer.

---

## Two-Part Solution

| Concept | Function | Applied To | Meaning |
|---------|----------|-----------|---------|
| **Energy Conservation** (compensation) | `ComputeEnergyConservation()` | Specular lobe | Multi-scatter weight W |
| **Energy Preservation** | `ComputeEnergyPreservation()` | Diffuse lobe | Attenuation by specular energy |

---

## Core Math: Multi-Scattering Compensation

**Turquin 2019, Eq. 16:**

```
              F0
W = 1 + F0 · ─────────
           E_single
```

- `E_single` = GGX single-scatter directional albedo (from LUT or analytic fit)
- `W` is multiplied onto Specular to restore energy lost to multi-scattering

**Split-Sum for E with Fresnel (Fdez-Aguera 2019):**

```
E_total = W · (E · F0 + Ef · (F90 - F0))
```

- `E` = pure GGX directional albedo (LUT .x)
- `Ef` = GGZ × Schlick (1-VoH)^5 directional albedo (LUT .y)
- This separates BRDF shape from Fresnel curve

---

## E Acquisition: Three Paths

### Path 1: Precomputed LUT (USE_ENERGY_CONSERVATION == 1)
4 textures, generated at startup or loaded from pre-baked data:

| Texture | Dim | Format | Index | Output | BxDF |
|---------|-----|--------|-------|--------|------|
| `ShadingEnergyGGXSpecTexture` | 2D 32×32 | R16G16 | (NoV, Roughness) | (E, Ef) | GGX Specular |
| `ShadingEnergyGGXGlassTexture` | 3D 32³ | R16G16 | (NoV, Roughness, IOR∈[1,3]) | (E_out→in, E_in→out) | GGX Glass |
| `ShadingEnergyClothSpecTexture` | 2D 32×32 | R16G16 | (NoV, Roughness) | (E, Ef≈0) | Cloth |
| `ShadingEnergyDiffuseTexture` | 2D 32×32 | R16 | (NoV, Roughness) | E | Diffuse (currently disabled) |

**LUT Precomputation** (`ShadingEnergyConservationTable.usf`, BUILD_ENERGY_TABLE permutations):
- Compute Shader with 2^14 = 16384 samples per texel
- GGX Spec: `ImportanceSampleVisibleGGX` → `GGXEvalReflection` → accumulate Weight=(GGX.x, GGX.x * Pow5(1-VoH))
- GGX Glass: Same VNDF sampling → `SampleRefraction` for both directions + `GGXEvalRefraction`
- Cloth: `CosineSampleHemisphere` → D_Charlie*Vis_Ashikhmin or D_InvGGX*Vis_Cloth
- Diffuse: Cosine sampling → `Diffuse_GGX_Rough` weighted

**C++ Pipeline** (`ShadingEnergyConservation.cpp`):
- `Init()` dispatches 4 CS passes or loads from `GEngine->GGXReflectionEnergyTexture` etc.
- CVars: `r.Shading.EnergyConservation`, `r.Shading.EnergyPreservation`, `r.Shading.EnergyConservation.RuntimeGeneration`
- `GetData()` returns `FShadingEnergyConservationData` bound to View UB
- Feature gating: enabled when Substrate is on, or `r.Material.EnergyConservation=1` for legacy

### Path 2: Analytic Approximation (USE_ENERGY_CONSERVATION == 2)
No texture sampling — pure ALU:

```hlsl
// GGX:
E  = 1.0 - saturate(pow(r, c/r) * ((r*c + 0.0266916) / (0.466495 + c)))
Ef = Pow5(1-c) * pow(2.36651 * pow(c, 4.7703*r) + 0.0387332, r)

// Cloth (InvGGX):
E = 0.526422 / ((-0.227114+r)*(-0.968835+r)*((5.38869-20.2835*c)*r) - (-1.18761-((2.58744-c)*c))) + 0.0615456
```

For OpenGL ES / platforms without independent samplers.

---

## ComputeFresnelEnergyTerms (ShadingEnergyConservationTemplate.ush:38-63)

```hlsl
struct FBxDFEnergyTerms {
    float3 W;  // multi-scatter compensation weight
    float3 E;  // total directional albedo (with Fresnel)
};

ComputeFresnelEnergyTerms(float2 E_lut, float3 F0, float3 F90):
    W = 1.0 + F0 * ((1 - E_lut.x) / E_lut.x)
    E = W * (E_lut.x * F0 + E_lut.y * (F90 - F0))
```

**Chromatic vs Achromatic versions**: Template instantiated twice:
- `FBxDFEnergyTermsRGB` (float3 W/E) — default
- `FBxDFEnergyTermsA` (float W/E) — for cases where color isn't needed (Cloth)

Controlled by `USE_ACHROMATIC_BXDF_ENERGY` define.

---

## Energy Preservation: Diffuse Attenuation

```hlsl
float ComputeEnergyPreservation(FBxDFEnergyTerms EnergyTerms) {
    return 1 - Luminance(EnergyTerms.E);
}
```

**Why Luminance(E) not E?** Metallic SpecularColor is colored (e.g. gold F0=(1.0, 0.76, 0.34)). Using `1-E` would cause color shift. Luminance ensures achromatic attenuation — metallic absorbed energy is truly absorbed, not passed to diffuse.

---

## ClearCoat: Double-Layer Energy Propagation

### Architecture
```
Incident light (E=1.0)
       │
  ┌────┴─────────────────┐
  │ ClearCoat Top Layer    │  IOR=1.5, F0=0.04
  │ Spec_coat *= W_coat    │  ← EnergyConservation
  │ Transmit = 1 - E_coat  │  ← EnergyPreservation
  └────┬─────────────────┘
       │ RefractClearCoatContext() — adjust dot products for refraction
       │ SimpleClearCoatTransmittance() — Beer-Lambert absorption
       ▼
  ┌─────────────────────┐
  │ Bottom Layer          │  Standard PBR
  │ Diffuse *= (1-E_bot)  │  ← EnergyPreservation
  │ Specular *= W_bot     │  ← EnergyConservation
  └─────────────────────┘
```

### RefractClearCoatContext (ShadingModels.ush:330-350)
**Key insight**: GGX BRDF only needs dot products (NoV, NoL, VoH, NoH), not full vectors. So refraction is propagated through dot products analytically:

```hlsl
half Eta = 1.0 / 1.5;
half RefractionBlendFactor = RefractBlendClearCoatApprox(Context.VoH);
half RefractionProjectionTerm = RefractionBlendFactor * Context.NoH;

RefractedContext.NoV = clamp(Eta * Context.NoV - RefractionProjectionTerm, 0.001, 1.0);
RefractedContext.NoL = clamp(Eta * Context.NoL - RefractionProjectionTerm, 0.001, 1.0);
RefractedContext.VoH = saturate(Eta * Context.VoH - RefractionBlendFactor);
RefractedContext.VoL = 2.0 * RefractedContext.VoH^2 - 1.0;
```

### SimpleClearCoatTransmittance (BRDF.ush:753-788)
Beer-Lambert absorption through clear coat medium:

```hlsl
float LayerThickness = 1.0;
float ThinDistance = LayerThickness * (rcp(NoV) + rcp(NoL));

// Derive extinction from BaseColor (which is reflectance at normal incidence, path=2*Thickness)
float3 TransmittanceColor = Diffuse_Lambert(BaseColor);
float3 ExtinctionCoefficient = -log(max(TransmittanceColor, 0.0001)) / (2.0 * LayerThickness);

// Optical depth relative to normal incidence baseline
float3 OpticalDepth = ExtinctionCoefficient * max(ThinDistance - 2.0 * LayerThickness, 0.0);
Transmittance = exp(-OpticalDepth);

// Only metals get absorption (ClearCoatCoverage = Metallic for legacy)
Transmittance = lerp(1.0, Transmittance, ClearCoatCoverage);
```

---

## Per-BxDF Energy Term Usage

| BxDF | Specular Energy | Diffuse Energy | Special |
|------|----------------|---------------|---------|
| DefaultLit | `ComputeGGXSpecEnergyTerms` → `*= W` | `*= (1-Lum(E))` | Standard |
| ClearCoat | Top: `W_coat`. Bottom: `W_bot` | `FresnelCoeff * Transmission * DefaultDiffuse` | Double-layer + Beer-Lambert |
| SubsurfaceProfile | Average roughness of 2 lobes → `W` | `*= (1-Lum(E))` | Uses average of dual-lobe roughness |
| Cloth | Lobe1: `ComputeGGXSpecEnergyTerms` → `*= W1`. Lobe2: `ComputeClothEnergyTerms` → `*= W2` | `lerp((1-Lum(E1)), (1-Lum(E2)), Cloth)` | Two independent lobes |
| Eye | `ComputeGGXSpecEnergyTerms` → `*= W` | `*= (1-Lum(E))` | Same as DefaultLit for energy |

---

## Furnace Test Validation (ShadingFurnaceTest.usf)

Runtime validation via `r.Shading.FurnaceTest 1`:

```
For each pixel on screen:
  Read GBuffer (Roughness, Normal, ShadingModelID)
  For each of 3 sampling strategies (GGX, Cosine, ClearCoat GGX):
    For each sample (NumSamplesPerSet, configurable):
      Generate light direction L using importance sampling
      Evaluate BxDF via GetDynamicLighting()
      Accumulate with MIS Power Heuristic weighting
  Output = FinalRadiance
  Ideal result: uniform color = InRadiance (0.5)
```

Any darkening indicates energy loss; brightening indicates energy creation.

---

## Complete Data Flow

```
Engine Startup
  ├─ [Prebaked] Load from GEngine->GGXReflectionEnergyTexture (UTexture2D RGBA16F)
  │   OR
  └─ [Runtime]  4× ComputeShader dispatches (16384 samples/texel, 32×32 or 32³)
      → 4 LUT textures in GShadingEnergyConservationResources

Per-Frame Init
  └─ ShadingEnergyConservation::Init()
     └─ Bind to ViewUniformShaderParameters:
        ShadingEnergyGGXSpecTexture, ShadingEnergyGGXGlassTexture,
        ShadingEnergyClothSpecTexture, ShadingEnergyDiffuseTexture,
        bShadingEnergyConservation, bShadingEnergyPreservation

Deferred Lighting (per pixel × per light)
  ├─ 1. Sample LUT: GGXEnergyLookup(Roughness, NoV) → (E, Ef)
  ├─ 2. Compute W = 1 + F0*(1-E)/E, E_total = W*(E*F0 + Ef*(F90-F0))
  ├─ 3. Lighting.Specular *= W        // EnergyConservation
  ├─ 4. Lighting.Diffuse  *= (1-Lum(E_total))  // EnergyPreservation
  └─ 5. [ClearCoat] RefractClearCoatContext + SimpleClearCoatTransmittance
```

---

## Key Source Files

| File | Role |
|------|------|
| `ShadingEnergyConservation.ush` | Entry point, LUT lookups, analytic fallbacks, chromatic/achromatic template instantiation |
| `ShadingEnergyConservationTemplate.ush` | FBxDFEnergyTerms struct, ComputeFresnelEnergyTerms, ComputeGGXSpecEnergyTerms, ComputeEnergyPreservation/Conservation |
| `ShadingEnergyConservationTable.usf` | CS for runtime LUT generation (4 permutations: GGXSpec=0, GGXGlass=1, Cloth=2, Diffuse=3) |
| `ShadingEnergyConservation.cpp/.h` | C++ Init/GetData/Debug, FShadingEnergyConservationResources, furnace test pass |
| `ShadingFurnaceTest.usf` | MIS-based reference integration for visual validation |
| `ShadingModels.ush` | All BxDF implementations showing energy term usage per model |
| `BRDF.ush` | SimpleClearCoatTransmittance, core D/G/F primitives |
| `SceneView.h` | LUT texture bindings in FViewUniformShaderParameters |

## References

- [1] Kulla & Conty, "Revisiting Physically Based Shading at Imageworks" (SIGGRAPH 2017) — Terminology + table-based approach
- [2] Turquin, "Practical Multiple Scattering Compensation for Microfacet Models" (2019) — Core formula: W = 1 + F0*(1-E)/E
- [3] Fdez-Aguera, "A Multiple-Scattering Microfacet Model for Real-Time Image Based Lighting" (JCGT 2019) — Split-sum for energy preservation
