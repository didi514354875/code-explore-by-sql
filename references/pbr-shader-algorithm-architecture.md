# UE PBR Shader Algorithm Architecture

## Key Source Files

| File | Role | Lines |
|------|------|-------|
| `Shaders/Private/BRDF.ush` (~821 lines) | Core microfacet BRDF primitives: D_GGX, Vis_SmithJoint, F_Schlick, EnvBRDF, SheenLTC, anisotropy helpers |
| `Shaders/Private/ShadingModels.ush` (~1112 lines) | All BxDF implementations: DefaultLit, ClearCoat, SubsurfaceProfile, Subsurface, Cloth, Eye, Hair, TwoSidedFoliage. Central dispatch via `IntegrateBxDF()` switch |
| `Shaders/Private/ShadingCommon.ush` (~220 lines) | ShadingModelID enum, F0/Metallic/DiffuseAlbedo conversions, FGBufferData struct field documentation |
| `Shaders/Private/ShadingEnergyConservation.ush` (~182 lines) | Energy compensation (multi-scattering) and preservation (diffuse vs specular competition) |
| `Shaders/Private/ShadingEnergyConservationTemplate.ush` (~145 lines) | Parameterized energy terms: FBxDFEnergyTerms{W, E}, ComputeGGXSpecEnergyTerms, ComputeClothEnergyTerms, ComputeEnergyPreservation/Conservation |
| `Shaders/Private/DeferredShadingCommon.ush` (~1279 lines) | GBuffer layout, FGBufferData struct (60 fields), encode/decode functions |
| `Shaders/Private/DeferredLightingCommon.ush` (~678 lines) | `AccumulateDynamicLighting()` — the main deferred light integration entry. `GetDynamicLighting()` wrapper. Shadow terms. |
| `Shaders/Private/DeferredLightPixelShaders.usf` (~561 lines) | Pixel shader entry points. Calls `GetDynamicLighting()` per light. Substrate path gating. |
| `Shaders/Private/RectLight.ush` (~704 lines) | Rect light: LTC matrix lookup, `RectGGXApproxLTC()`, irradiance lambert, spherical rect projection |
| `Shaders/Private/RectLightIntegrate.ush` (~225 lines) | Rect light BxDF integration: CreateAreaLight, IntegrateBxDF for rect, reference path Monte Carlo |
| `Shaders/Private/CapsuleLightIntegrate.ush` (~276 lines) | Capsule light BxDF integration: CreateAreaLight, analytical + reference paths |
| `Shaders/Private/DynamicLightingCommon.ush` (~108 lines) | Light attenuation helpers: RadialAttenuation, SpotAttenuation, GetLightInfluenceMask |

## Algorithm Architecture

### 1. Material Parameter → Physical Parameter (ShadingCommon.ush)

```
BaseColor + Metallic + Specular → F0, DiffuseColor, SpecularColor
  F0 = lerp(0.08 * Specular, BaseColor, Metallic)  // Fresnel at normal incidence
  DiffuseColor = BaseColor * (1 - Metallic)          // Metals have no diffuse
  SpecularColor = F0                                  // Used in Schlick
```

### 2. Core Microfacet BRDF — D/G/F (BRDF.ush)

Standard specular: `Specular = D_GGX(a2, NoH) * Vis_SmithJointApprox(a2, NoV, NoL) * F_Schlick(SpecularColor, VoH)`

- **D_GGX**: `a2 / (PI * d*d)` where `d = (NoH * a2 - NoH) * NoH + 1`, `a2 = Roughness^4`. Long-tail distribution.
- **Vis_SmithJointApprox**: Returns G/(4·NoV·NoL). Schlick approximation of Smith joint visibility.
- **F_Schlick**: `Fc + (1-Fc) * SpecularColor` where `Fc = (1-VoH)^5`. F90 = saturate(50 * SpecularColor.g) — below 2% is shadowing.
- **Anisotropic variants**: D_GGXaniso(ax, ay, ...), Vis_SmithJointAniso(ax, ay, ...). Kulla 2017 parameterization.

### 3. DefaultLitBxDF Flow (ShadingModels.ush:203-288)

```
1. Init BxDFContext (all dot products: N/V/L/H + anisotropic X/Y variants)
2. Diffuse = Diffuse_Lambert(DiffuseColor) * NoL  OR  Diffuse_GGX_Rough(...)
3. Specular = SpecularGGX(Roughness, SpecularColor, Context, AreaLight)
   - RectLight → RectGGXApproxLTC (LTC analytical integration)
   - Aniso → D_GGXaniso * Vis_SmithJointAniso * F_Schlick
   - Standard → D_GGX * Vis_SmithJointApprox * F_Schlick
4. EnergyTerms = ComputeGGXSpecEnergyTerms(Roughness, NoV, SpecularColor)
5. Diffuse *= ComputeEnergyPreservation(EnergyTerms)   // (1 - specular energy)
6. Specular *= ComputeEnergyConservation(EnergyTerms)   // multi-scatter compensation W
```

### 4. Energy Conservation System

**Problem 1: Multi-scattering energy loss** — Standard GGX only models single scattering. White material at roughness=1 appears grey.

- Solution: `W = 1 + F0 * (1-E.x)/E.x` from LUT lookup `GGXEnergyLookup(Roughness, NoV)`
- Specular *= W (compensates lost energy)
- Ref: Turquin 2019, Kulla 2017

**Problem 2: Diffuse-Specular energy competition** — Energy reflected by specular shouldn't appear in diffuse.

- Solution: `EnergyPreservation = 1 - Luminance(EnergyTerms.E)` where E is specular directional albedo
- Diffuse *= (1 - E_specular)
- Ref: Fdez-Aguera 2019 split-sum

**LUTs**: `ShadingEnergyGGXSpecTexture`, `ShadingEnergyClothSpecTexture`, `ShadingEnergyGGXGlassTexture`
- Analytical fallback (USE_ENERGY_CONSERVATION==2) exists but less accurate

### 5. Area Light Integration — LTC (RectLight.ush)

Linearly Transformed Cosines (Heitz 2016):
1. Precompute M^-1 matrix mapping GGX → cosine distribution (stored in `GGXLTCMat` LUT)
2. Transform rect polygon vertices by M^-1
3. Analytical cosine-weighted integration over transformed polygon
4. Amplitude correction from `GGXLTCAmp` LUT
5. Key function: `RectGGXApproxLTC(Roughness, SpecularColor, N, V, Rect, Texture)`

Capsule lights: Multiple sphere+cylinder representative point method, with energy normalization.

### 6. IBL — Split-Sum (BRDF.ush:612-667)

`EnvBRDF(SpecularColor, Roughness, NoV)`:
- Sample `PreIntegratedGF` LUT at (NoV, Roughness) → (A, B)
- Result = SpecularColor * A + F90 * B
- Mobile fallback: `EnvBRDFApproxLazarov` — pure ALU, no texture (COD:BO2 Lazarov 2013)
- Fully rough optimization: `EnvBRDFApproxFullyRough` — diffuse absorbs 45% of specular

### 7. Shading Model Dispatch (ShadingModels.ush:1072-1100)

`IntegrateBxF...[truncated]` switch on `GBuffer.ShadingModelID`:
- DEFAULT_LIT/SINGLELAYERWATER/THIN_TRANSLUCENT → DefaultLitBxDF
- SUBSURFACE → DefaultLit + Beer-Lambert transmission + wrapped diffuse + in-scatter
- SUBSURFACE_PROFILE → Dual-lobe GGX + Burley diffuse + pre-integrated SSS transmission + HG phase function
- CLEAR_COAT → Two-layer: top IOR=1.5 GGX + bottom standard GGX with Fresnel attenuation + refraction propagation via dot products + Beer-Lambert absorption
- CLOTH → Lerp(Standard GGX, InvGGX+Vis_Cloth+FuzzColor Fresnel, Cloth factor)
- EYE → CausticNormal + IrisNormal + IrisMask + GGX specular
- HAIR → HairBsdf.ush (R/TT/TRT lobes via HairShading())
- TWOSIDED_FOLIAGE → DefaultLit + wrapped diffuse transmission with GGX scatter

### 8. Call Chain: Deferred Light Pixel Shader → BxDF

```
DeferredLightPixelShaders.usf::MainPS()
  → GetDynamicLighting(TranslatedWorldPosition, CameraVector, GBuffer, AO, LightData, LightAttenuation, ...)
    → AccumulateDynamicLighting(...)
      → GetShadowTerms(...)           // shadow + contact shadow
      → if (RectLight) IntegrateBxDF(GBuffer, N, V, Rect, Shadow, SourceTexture)
         else IntegrateBxDF(GBuffer, N, V, Capsule, Shadow, bInverseSquared)
           → ShadingModels.ush::IntegrateBxF...[truncated] switch(ShadingModelID)
             → XxxxBxDF(GBuffer, N, V, AreaLight, Shadow)
               → SpecularGGX / RectGGXApproxLTC + energy terms
      → LightAccumulator_AddSplit(Diffuse, Specular, Transmission, LightColor*Shadow)
```

### 9. Key LUT Textures

| Texture | Index | Used By |
|---------|-------|---------|
| PreIntegratedGF | (NoV, Roughness) → (A, B) | EnvBRDF IBL |
| GGXLTCMat / GGXLTCAmp | (NoV, Roughness) | Rect light specular |
| ShadingEnergyGGXSpecTexture | (NoV, Roughness) → (E, Ef) | Energy compensation |
| ShadingEnergyClothSpecTexture | (NoV, Roughness) | Cloth energy |
| SSProfilesPreIntegratedTexture | (NoL, Curvature, ProfileId) | SSS profile |
| PreIntegratedBRDF | (NoL, Opacity) | Fast subsurface |
| SheenLTCTexture | (NoV, Roughness) | Sheen BSDF (Zeltner 2022) |

## Substrate Note

All legacy BxDFs marked `// UE_DEPRECATED 5.7 - Deprecated by Substrate`. Substrate replaces the ShadingModelID dispatch with `SubstrateEvaluateBSDFCommon()` and `SubstrateDeferredLighting()`. The legacy path remains active when Substrate is disabled or in backward-compatible mode.
