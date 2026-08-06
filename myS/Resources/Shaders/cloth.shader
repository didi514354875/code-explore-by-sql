明日方舟 终末地 服装
diffuse 分量分析
AO * ShadowTex.y * camRampTexW      // camShadowRadiance
// 相当于主光radiance加上收ao 自shadow影响的辅助光  作为两层shadowDiffuse过渡  主要受到ramp图片w通道控制
saturate(rampTex.w + camShadowRadiance)  mainRadiance + camShadowRadiance  //   rampRadiance

min(rampTex.w, min(AO, ShadowTex.y))          // rampShadowRadiance

diffuseColor _2ndDiffuseColor   shadowDiffuseColor  _2ndShadowDiffuseColor     _2nd 增强了饱和度

//主光辅助光 radiance在shadow区域的过渡
lerp(_2ndShadowDiffuseColor, shadowDiffuseColor, rampRadiance)    // combineShadowDiffuseColor

//主光radiance的过渡
lerp(combineShadowDiffuseColor, diffuseColor, rampShadowRadiance) //  diffuseColor
lerp(1, rampTex.rgb, rampTexRange) * curDiffuseColor  *  curDiffuseIntensity / max(rampCurDiffuseIntensity, 0.001) // diffuseColor  考虑ramp并调整亮度不被ramp影响

// 在场景阴影中此时不考虑主光影响，只有辅助光印象并且
lerp(shadowDiffuseColor, _2ndDiffuseColor, camShadowRadiance)   // diffuseInSceneShadow

lerp(diffuseInSceneShadow, diffuseColor, curSceneShadow)   // 最终的diffuseColor


// 主光受到漫反射强度对饱和度的影响
lerp(rIntesity, lightColor, rampShadowRadiance)

// 环境光过渡
lerp(shColor, 1,  rampShadowRadiance * min(cb0[161].y, l(1.0000)))    shCol

// sceneshadow 影响光照成分
lerp(ndotSky * ambientCol * mulIntesity1 * cb0[160].w, lightAndAmbientCol * cb0[160].y, curSceneShadow)    // ambientAndLightRadiance








附加光源    cb3[r8.w + 6].w < 2 对角色起作用


cb3[r8.w + 6].w == 1   no directional

cb3[r10.y + 6].z    lightLength  光源长度

no directional + 光源长度 > 0 area light



0 单独的diffusecolor逻辑 有specular                //没有阴影





附加光源不论是点光源还是聚光灯 
光源render方式0 没有阴影，用场景阴影缩放了的lightcolor， radiance没有ramp， 用ramp贴图调整了的diffusecolor，  普通的specular
光源render方式1 简单wrapped diffuse， 只考虑了基本的（diffuseColor shadowDiffuseColor）, 普通的specular
光源render方式2 受到阴影，高光都可以控制材质roughnness,影响特定区域，  但是没有漫反射
光源render方式3 受到阴影，可能处理背光 （shadowDiffuseColor为0， diffuseColor），  没有高光
光源render方式4 直接通过ndotl混合光照颜色， 没有所谓后续高光漫反射计算



明日方舟 终末地



Shader hash 275d3f82-7a0adecd-7659c1ff-802353cc

vs_5_0
      dcl_globalFlags refactoringAllowed
      dcl_constantbuffer cb0[67], immediateIndexed
      dcl_constantbuffer cb1[27], dynamicIndexed
      dcl_constantbuffer cb2[52], immediateIndexed
      dcl_resource_structured t0, 16
      dcl_input v0.xyz                      // positionOS
      dcl_input v1.xy                       // uv
      dcl_input v2.xyz                          // normalOS   如果法线压缩（Octahedron normal endoding ）并编码到 v2.x 两个10bit中 最后一个10bit存储存储切线位置也是类似于八面体编码只不过只需要考虑2d平面上就可以，因为切线是法线的垂直向量（切线在2d中表示为(a,b), 编码到a+b=1的直线上，只需要存储a）
      dcl_input v3.xyzw                         // TangentOS  
      dcl_input v4.xyz                              //oldPositionOS
      dcl_input_sgv v5.x, instanceid               // SV_INSTANCEID
      dcl_input v6.xyzw                             // blendWeights
      dcl_input v7.xyzw                             // blendIndices
      dcl_output o0.xy                              // uv
      dcl_output o1.xyz                             // positionWS
      dcl_output o2.xyz                             // normalWS
      dcl_output o3.xyzw                            // tangentWS
      dcl_output o4.xyz                             // viewDirWS
      dcl_output o5.xyz                             // nonJitterScreenPos
      dcl_output o6.xyz                             // oldScreenPos
      dcl_output o7.xyz                             // normalOS
      dcl_output o8.xyz                             // positionOS
      dcl_output_siv o9.xyzw, position              // positionCS
      dcl_output o10.x                              // instanceID
      dcl_temps 12
   0: and r0.x, v2.x, l(2.0000)             //  从v2.x中提取第二位（判断是否使用压缩法线/切线）
   1: ult r0.x, l(0), r0.x                 // r0.x > 0     
   2: ibfe r0.yzw, l(0, 10, 10, 10), l(0, 0, 10, 20), v2.xxxx     // 位域提取：从v2.x解包法线/切线  
   3: ushr r1.x, v2.x, l(31)                                // 提取符号位（判断是否需要取反）
   4: itof r0.yzw, r0.yyzw                                                  //输出范围：-512.0 ~ 511.0
   5: mul r1.yzw, r0.yyzw, l(0.0000, 0.0020, 0.0020, 0.0020)          //r0.yyzw / 1023 * 2   计算公式：2/1023 ≈ 0.00195 ≈ 0.002 将10位有符号数映射到[-1.0, 1.0]范围
   6: add r2.xyz, -abs(r1.yzyy), l(1.0000, 1.0000, 1.0000, 0.0000)     //操作：计算 1 - |x| 和 1 - |y|                      // OctahedronToUnitVector 函数开始
   7: add r3.z, -abs(r1.z), r2.x                            // 计算 (1 - |x|) - |y|
   8: lt r2.x, r3.z, l(0)                                       // 如果(1 - |x| - |y|) < 0，说明需要重新计算基向量
   9: ge r0.yz, r0.yyzy, l(0, 0, 0, 0)                          // 比较解压后的XY分量是否 >= 0，结果存入r0.yz; 目的：检测是否需要符号翻转（处理有符号10位整数）
  10: and r0.yz, r0.yyzy, l(0.0000, 1.0000, 1.0000, 0.0000)     // 效果：r0.y = (X >= 0 ? 1 : 0), r0.z = (Y >= 0 ? 1 : 0)
  11: mad r0.yz, r0.yyzy, l(0.0000, 2.0000, 2.0000, 0.0000), l(0.0000, -1.0000, -1.0000, 0.0000)    //将布尔值转换为方向系数：公式：value = bool * 2.0 - 1.0    // 0 → -1.0 (false时取负)1 → +1.0 (true时保持正)
  12: mul r0.yz, r0.yyzy, r2.yyzy
  13: movc r3.xy, r2.xxxx, r0.yzyy, r1.yzyy   //  
  14: dp3 r0.y, r3.xyzx, r3.xyzx
  15: rsq r0.y, r0.y
  16: mul r2.xyz, r0.yyyy, r3.xyzx                // // OctahedronToUnitVector  结束  从八面体编码冲解码了 法线 normalOS
  17: mad r3.xyz, r3.yzxy, r0.yyyy, -r2.zxyz            //  normal.yzx - normal.zxy           这种方式构造垂直向量 cross(normal, float3(1,1,1))     perpendicular
  18: dp3 r0.y, r3.xyzx, r2.xyzx                            // dot(perpendicular, normal.xyz)
  19: add r3.xyz, -r0.yyyy, r3.xyzx             // perpendicular - dot(perpendicular, normal.xyz)   //公式：tangent = bitangent - dot(bitangent, normal)*normal 正交修正   == perpendicular
  20: dp3 r0.y, r3.xyzx, r3.xyzx
  21: rsq r0.y, r0.y
  22: mul r3.xyz, r0.yyyy, r3.xyzx         //     normalize(perpendicular) 
  23: mul r4.xyz, r2.zxyz, r3.yzxy                          // 
  24: mad r4.xyz, r2.yzxy, r3.zxyz, -r4.xyzx            // cross(normalOS, perpendicular)   biPerpendicular
  25: dp3 r0.y, r4.xyzx, r4.xyzx
  26: rsq r0.y, r0.y
  27: mul r4.xyz, r0.yyyy, r4.xyzx              //   biPerpendicular
  28: lt r0.y, r0.w, l(0)                       // z < 0
  29: movc r0.y, r0.y, l(-1.0000), l(1.0000)   // z < 0 ? -1 : 1
  30: dp2 r0.z, r1.wwww, r0.yyyy    // (z < 0 ? -1 : 1) * r1.w  factor
  31: add r5.x, -r0.z, l(1.0000)    //1 - factor
  32: add r0.z, -abs(r5.x), l(1.0000)   // 1 - abs(1 - factor)
  33: mul r5.y, r0.z, r0.y                                      // (z < 0 ? -1 : 1) * (1 - abs(1 - factor))
  34: dp2 r0.y, r5.xyxx, r5.xyxx
  35: rsq r0.y, r0.y
  36: mul r0.yz, r0.yyyy, r5.xxyx                                   // normalize
  37: mul r1.yzw, r4.xxyz, r0.zzzz
  38: mad r3.xyz, r0.yyyy, r3.xyzx, r1.yzwy             //合成最终切线向量：t = t1*scale_x + t2*scale_z
  39: itof r0.y, r1.x
  40: mad r3.w, r0.y, l(2.0000), l(-1.0000)           // 符号
  41: movc r0.yzw, r0.xxxx, r2.xxyz, v2.xxyz                            //  normalOS    是否压缩
  42: movc r1.xyzw, r0.xxxx, r3.xyzw, v3.xyzw                         // tangentOS  是否压缩
  43: ishl r0.x, v5.x, l(4)                                                 // instanceId << 4
{
  44: if_nz cb1[r0.x + 4].w
  45:   imad r2.xyzw, v7.xyzw, l(3, 3, 3, 3), cb1[r0.x + 5].xxxx
  46:   imad r3.xyzw, v7.xyzw, l(3, 3, 3, 3), cb1[r0.x + 5].yyyy
  47:   ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r4.xyzw, r2.x, l(0), t0.xyzw
  48:   iadd r5.xy, r2.xxxx, l(1, 2, 0, 0)
  49:   ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r6.xyzw, r5.x, l(0), t0.xyzw
  50:   ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r5.xyzw, r5.y, l(0), t0.xyzw
  51:   ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r7.xyzw, r3.x, l(0), t0.xyzw
  52:   iadd r8.xy, r3.xxxx, l(1, 2, 0, 0)
  53:   ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r9.xyzw, r8.x, l(0), t0.xyzw
  54:   ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r8.xyzw, r8.y, l(0), t0.xyzw
  55:   uge r10.xy, cb1[r0.x + 4].wwww, l(2, 4, 0, 0)
  56:   if_nz r10.x
  57:     ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r11.xyzw, r2.y, l(0), t0.xyzw
  58:     mul r11.xyzw, r11.xyzw, v6.yyyy
  59:     mad r4.xyzw, r4.xyzw, v6.xxxx, r11.xyzw
  60:     iadd r2.xy, r2.yyyy, l(1, 2, 0, 0)
  61:     ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r11.xyzw, r2.x, l(0), t0.xyzw
  62:     mul r11.xyzw, r11.xyzw, v6.yyyy
  63:     mad r6.xyzw, r6.xyzw, v6.xxxx, r11.xyzw
  64:     ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r11.xyzw, r2.y, l(0), t0.xyzw
  65:     mul r11.xyzw, r11.xyzw, v6.yyyy
  66:     mad r5.xyzw, r5.xyzw, v6.xxxx, r11.xyzw
  67:     ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r11.xyzw, r3.y, l(0), t0.xyzw
  68:     mul r11.xyzw, r11.xyzw, v6.yyyy
  69:     mad r7.xyzw, r7.xyzw, v6.xxxx, r11.xyzw
  70:     iadd r2.xy, r3.yyyy, l(1, 2, 0, 0)
  71:     ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r11.xyzw, r2.x, l(0), t0.xyzw
  72:     mul r11.xyzw, r11.xyzw, v6.yyyy
  73:     mad r9.xyzw, r9.xyzw, v6.xxxx, r11.xyzw
  74:     ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r11.xyzw, r2.y, l(0), t0.xyzw
  75:     mul r11.xyzw, r11.xyzw, v6.yyyy
  76:     mad r8.xyzw, r8.xyzw, v6.xxxx, r11.xyzw
  77:   endif
  78:   if_nz r10.y
  79:     ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r10.xyzw, r2.z, l(0), t0.xyzw
  80:     ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r11.xyzw, r2.w, l(0), t0.xyzw
  81:     mul r11.xyzw, r11.xyzw, v6.wwww
  82:     mad r10.xyzw, r10.xyzw, v6.zzzz, r11.xyzw
  83:     add r4.xyzw, r4.xyzw, r10.xyzw
  84:     iadd r2.xyzw, r2.zwzw, l(1, 1, 2, 2)
  85:     ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r10.xyzw, r2.x, l(0), t0.xyzw
  86:     ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r11.xyzw, r2.y, l(0), t0.xyzw
  87:     mul r11.xyzw, r11.xyzw, v6.wwww
  88:     mad r10.xyzw, r10.xyzw, v6.zzzz, r11.xyzw
  89:     add r6.xyzw, r6.xyzw, r10.xyzw
  90:     ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r10.xyzw, r2.z, l(0), t0.xyzw
  91:     ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r2.xyzw, r2.w, l(0), t0.xyzw
  92:     mul r2.xyzw, r2.xyzw, v6.wwww
  93:     mad r2.xyzw, r10.xyzw, v6.zzzz, r2.xyzw
  94:     add r5.xyzw, r2.xyzw, r5.xyzw
  95:     ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r2.xyzw, r3.z, l(0), t0.xyzw
  96:     ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r10.xyzw, r3.w, l(0), t0.xyzw
  97:     mul r10.xyzw, r10.xyzw, v6.wwww
  98:     mad r2.xyzw, r2.xyzw, v6.zzzz, r10.xyzw
  99:     add r7.xyzw, r2.xyzw, r7.xyzw
 100:     iadd r2.xyzw, r3.zwzw, l(1, 1, 2, 2)
 101:     ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r3.xyzw, r2.x, l(0), t0.xyzw
 102:     ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r10.xyzw, r2.y, l(0), t0.xyzw
 103:     mul r10.xyzw, r10.xyzw, v6.wwww
 104:     mad r3.xyzw, r3.xyzw, v6.zzzz, r10.xyzw
 105:     add r9.xyzw, r3.xyzw, r9.xyzw
 106:     ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r3.xyzw, r2.z, l(0), t0.xyzw
 107:     ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r2.xyzw, r2.w, l(0), t0.xyzw
 108:     mul r2.xyzw, r2.xyzw, v6.wwww
 109:     mad r2.xyzw, r3.xyzw, v6.zzzz, r2.xyzw
 110:     add r8.xyzw, r2.xyzw, r8.xyzw
 111:   endif
 112:   mov r2.xyz, v0.xyzx
 113:   mov r2.w, l(1.0000)
 114:   dp4 r3.x, r4.xyzw, r2.xyzw
 115:   dp4 r3.y, r6.xyzw, r2.xyzw
 116:   dp4 r3.z, r5.xyzw, r2.xyzw                   // positionOS
 117:   dp4 r7.x, r7.xyzw, r2.xyzw
 118:   dp4 r7.y, r9.xyzw, r2.xyzw
 119:   dp4 r7.z, r8.xyzw, r2.xyzw                   // oldPositionOS
 120:   dp3 r2.x, r4.xyzx, r0.yzwy
 121:   dp3 r2.y, r6.xyzx, r0.yzwy
 122:   dp3 r2.z, r5.xyzx, r0.yzwy
 123:   dp3 r2.w, r4.xyzx, r1.xyzx
 124:   dp3 r3.w, r6.xyzx, r1.xyzx
 125:   dp3 r1.z, r5.xyzx, r1.xyzx
 126:   mov r1.x, r2.w
 127:   mov r1.y, r3.w
}
 128: else
 129:   mov r7.xyz, v4.xyzx                                                 // oldPositionOS
 130:   mov r3.xyz, v0.xyzx                                                 // positionOS
 131:   mov r2.xyz, r0.yzwy                                                 // normalOS
 132: endif

 133: mul r4.xyz, r3.yyyy, cb1[r0.x + 1].xyzx                                   // 
 134: mad r4.xyz, cb1[r0.x + 0].xyzx, r3.xxxx, r4.xyzx
 135: mad r4.xyz, cb1[r0.x + 2].xyzx, r3.zzzz, r4.xyzx
 136: add r4.xyz, r4.xyzx, cb1[r0.x + 3].xyzx                                 // positionWS
 137: mul r5.xyzw, r4.yyyy, cb0[17].xyzw
 138: mad r5.xyzw, cb0[16].xyzw, r4.xxxx, r5.xyzw
 139: mad r5.xyzw, cb0[18].xyzw, r4.zzzz, r5.xyzw
 140: add o9.xyzw, r5.xyzw, cb0[19].xyzw                         // positionCS
 141: add r5.xyz, -r4.xyzx, cb0[32].xyzx                         // worldCameraPos - positionWS             // viewDirWS  
 142: add r6.x, -r5.x, cb0[0].z
 143: add r6.y, -r5.y, cb0[1].z
 144: add r6.z, -r5.z, cb0[2].z                                  // 相机相关矩阵
 145: mad r5.xyz, cb0[66].wwww, r6.xyzx, r5.xyzx                // lerp(viewDirWS, cb0[0]cb0[1]cb0[2].z，cb0[66].wwww )     viewDirWS              cb0[66].w  unity_OrthoParams.w
 146: dp3 r2.w, r5.xyzx, r5.xyzx
 147: rsq r2.w, r2.w
 148: mul o4.xyz, r2.wwww, r5.xyzx                                  // normalize(viewDirWS)
 149: mad o0.xy, v1.xyxx, cb2[51].xyxx, cb2[51].zwzz                // uv
 150: mul r5.xyz, r2.yyyy, cb1[r0.x + 1].xyzx
 151: mad r2.xyw, cb1[r0.x + 0].xyxz, r2.xxxx, r5.xyxz
 152: mad r2.xyz, cb1[r0.x + 2].xyzx, r2.zzzz, r2.xywx
 153: dp3 r2.w, r2.xyzx, r2.xyzx
 154: max r2.w, r2.w, l(0.0000)
 155: rsq r2.w, r2.w
 156: mul o2.xyz, r2.wwww, r2.xyzx                                  // normalWS      
 157: mul r2.xyz, r1.yyyy, cb1[r0.x + 1].xyzx
 158: mad r2.xyz, cb1[r0.x + 0].xyzx, r1.xxxx, r2.xyzx
 159: mad r1.xyz, cb1[r0.x + 2].xyzx, r1.zzzz, r2.xyzx
 160: dp3 r2.x, r1.xyzx, r1.xyzx
 161: max r2.x, r2.x, l(0.0000)
 162: rsq r2.x, r2.x
 163: mul o3.xyz, r1.xyzx, r2.xxxx                                    // tangentWS
 164: mul r1.xyz, r4.yyyy, cb0[25].xywx
 165: mad r1.xyz, cb0[24].xywx, r4.xxxx, r1.xyzx
 166: mad r1.xyz, cb0[26].xywx, r4.zzzz, r1.xyzx
 167: add o5.xyz, r1.xyzx, cb0[27].xywx                         // _NonJitterVP  nonJitterScreenPos  ？
 168: lt r1.x, cb1[r0.x + 10].x, l(1.0000)
 169: movc r1.xyz, r1.xxxx, r3.xyzx, r7.xyzx                    // 选择positionOS 还是oldPositionOS
 170: mul r2.xyzw, r1.yyyy, cb1[r0.x + 7].xyzw
 171: mad r2.xyzw, cb1[r0.x + 6].xyzw, r1.xxxx, r2.xyzw
 172: mad r2.xyzw, cb1[r0.x + 8].xyzw, r1.zzzz, r2.xyzw
 173: add r2.xyzw, r2.xyzw, cb1[r0.x + 9].xyzw
 174: mul r1.xyz, r2.yyyy, cb0[38].xywx
 175: mad r1.xyz, cb0[37].xywx, r2.xxxx, r1.xyzx
 176: mad r1.xyz, cb0[39].xywx, r2.zzzz, r1.xyzx
 177: mad o6.xyz, cb0[40].xywx, r2.wwww, r1.xyzx                       // oldPositionCS
 178: mov o3.w, r1.w
 179: mov o1.xyz, r4.xyzx                                               // positionWS
 180: mov o7.xyz, r0.yzwy                                                //  normalOS
 181: mov o8.xyz, v0.xyzx                                               // positionOS
 182: mov o10.x, v5.x                                                   // instanceID
 183: ret






Shader hash 4a07f45e-acdaf13f-0d615342-a3678a44

ps_5_0
      dcl_globalFlags refactoringAllowed
      dcl_constantbuffer cb0[181], immediateIndexed
      dcl_constantbuffer cb1[30], dynamicIndexed
      dcl_constantbuffer cb2[3], immediateIndexed
      dcl_constantbuffer cb3[2054], dynamicIndexed
      dcl_constantbuffer cb4[369], dynamicIndexed
      dcl_constantbuffer cb5[27], immediateIndexed
      dcl_sampler s0, mode_default
      dcl_sampler s1, mode_default
      dcl_sampler s2, mode_comparison
      dcl_sampler s3, mode_default
      dcl_sampler s4, mode_default
      dcl_sampler s5, mode_default
      dcl_sampler s6, mode_default
      dcl_sampler s7, mode_default
      dcl_sampler s8, mode_default
      dcl_sampler s9, mode_default
      dcl_resource_structured t0, 4
      dcl_resource_texture2d (float,float,float,float) t1       // DepthStencilTexture
      dcl_resource_texture2d (float,float,float,float) t2       // shadow相关 r通道是场景阴影 g通道是角色自阴影
      dcl_resource_texture3d (float,float,float,float) t3       //
      dcl_resource_texture3d (float,float,float,float) t4       // 
      dcl_resource_texture3d (float,float,float,float) t5       // 
      dcl_resource_texture2d (float,float,float,float) t6       // ramp图
      dcl_resource_texture2d (float,float,float,float) t7       // 
      dcl_resource_texture2d (float,float,float,float) t8       // 水点控制  水点法线等
      dcl_resource_texture2d (float,float,float,float) t9       // 水流控制  水流法线等
      dcl_resource_texture2d (float,float,float,float) t10      // 基础色 baseColor
      dcl_resource_texture2d (float,float,float,float) t11      // 可能的pbr参数   r是金属度    a 光滑度 
      dcl_resource_texture2d (float,float,float,float) t12      // 法线贴图 normalMap
      dcl_resource_texturecube (float,float,float,float) t13    // 环境贴图
      dcl_resource_texture2d (float,float,float,float) t14      // 
      dcl_resource_texture3d (float,float,float,float) t15      // 
      dcl_input_ps linear v0.xy                             // uv
      dcl_input_ps linear v1.xyz                            // positionWS
      dcl_input_ps linear v2.xyz                            // normalWS
      dcl_input_ps linear v3.xyzw                           // tangentWS
      dcl_input_ps linear v4.xyz                            // viewDirWS
      dcl_input_ps linear v5.xyz                            // nonJitterScreenPos
      dcl_input_ps linear v6.xyz                            // oldScreenPos
      dcl_input_ps linear v7.xyz                            // normalOS
      dcl_input_ps linear v8.xyz                                // positionOS
      dcl_input_ps_siv linear noperspective v9.xyw, position       // positionCS screepos
      dcl_input_ps nointerpolation v10.x                        // instanceID                           
      dcl_input_ps_sgv nointerpolation v11.x, isfrontface      //SV_ISFRONTFACE
      dcl_output o0.xyzw
      dcl_output o1.xyzw
      dcl_temps 32
      dcl_indexableTemp x0[8], 4
   0: sample_b(texture2d)(float,float,float,float) r0.xyzw, v0.xyxx, t10.xyzw, s5, cb0[88].x    //SAMPLE_TEXTURECUBE_LOD        baseTex
   1: sample_b(texture2d)(float,float,float,float) r1.xyzw, v0.xyxx, t11.xyzw, s6, cb0[88].x    // 可能的pbr参数   pbrParam
   2: add r2.xy, -r1.wxww, l(1.0000, 1.0000, 0.0000, 0.0000)              // 1 - r1.wx      (roughness, 1 - metallic)
   3: mul r0.xyzw, r0.xyzw, cb5[26].xyzw                                // baseColor
   4: mul r3.xyz, r0.xyzx, cb5[5].yyyy                                  // shadowBaseCol
   5: dp3 r2.z, r3.xyzx, l(0.2127, 0.7152, 0.0722, 0.0000)             // dot(baseColor, float3(0.2127, 0.7152, 0.0722)) brightness
   6: mad r3.xyz, r0.xyzx, cb5[5].yyyy, -r2.zzzz                            // 
   7: mad r3.xyz, cb5[5].zzzz, r3.xyzx, r2.zzzz                                 // lerp(brightness, baseColor, cb5[5].z)              // saturation调整    shadowBaseColor
   8: sample_b(texture2d)(float,float,float,float) r4.xyz, v0.xyxx, t12.xywz, s7, cb0[88].x               // normalTex
   9: mul r4.x, r4.x, r4.z                                                                                              
  10: mad r2.zw, r4.xxxy, l(0.0000, 0.0000, 2.0000, 2.0000), l(0.0000, 0.0000, -1.0000, -1.0000) // normalTex
  11: dp2 r3.w, r2.zwzz, r2.zwzz
  12: min r3.w, r3.w, l(1.0000)
  13: add r3.w, -r3.w, l(1.0000)
  14: sqrt r3.w, r3.w
  15: max r3.w, r3.w, l(0.0000)
  16: mul r2.zw, r2.zzzw, cb5[0].wwww                           // 应用法线强度
  17: ishl r4.x, v10.x, l(4)                                    // 
  18: add r4.yz, v1.xxzx, -cb1[r4.x + 3].xxzx                   // 计算世界坐标xz分量与实例位置偏移的差值（v1.xyz为世界坐标）  objectDir
  19: dp3 r4.w, v2.xyzx, v2.xyzx
  20: rsq r5.x, r4.w
  21: mul r5.xyz, r5.xxxx, v2.xyzx                   // normalize(normalWS)
  22: dp2 r5.w, r4.yzyy, r4.yzyy                        // 计算xz平面偏移向量的倒数长度
  23: max r5.w, r5.w, l(0.0000)
  24: rsq r5.w, r5.w
  25: mul r4.yz, r4.yyzy, r5.wwww                   // normalize(r4.yz)      objectDir
  26: dp3 r5.w, v4.xyzx, v4.xyzx
  27: max r5.w, r5.w, l(0.0000)
  28: rsq r5.w, r5.w
  29: mul r6.xyz, r5.wwww, v4.xyzx              // normalize(viewDirWS)
  30: sqrt r4.w, r4.w
  31: max r4.w, r4.w, l(0.0000)
  32: div r4.w, l(1.0000, 1.0000, 1.0000, 1.0000), r4.w  // 计算法线长度的倒数（1/长度）
  33: lt r6.w, l(0), v3.w                                   // 检查切线w分量（副切线方向标志）
  34: movc r6.w, r6.w, l(1.0000), l(-1.0000)
  35: ge r7.x, cb1[r4.x + 5].w, l(0)
  36: movc r7.x, r7.x, l(1.0000), l(-1.0000)           // 确定实例级的方向系数（1或-1）
  37: mul r6.w, r6.w, r7.x                              // 综合切线方向和实例方向的符号
  38: mul r7.xyz, v2.zxyz, v3.yzxy
  39: mad r7.xyz, v2.yzxy, v3.zxyz, -r7.xyzx          //// 完成副切线计算：bitangent = cross(normal, tangent)
  40: mul r7.xyz, r6.wwww, r7.xyzx
  41: mul r8.xyz, r4.wwww, v3.xyzx                      // tangent
  42: mul r7.xyz, r4.wwww, r7.xyzx                      // bitangent
  43: mul r9.xyz, r4.wwww, v2.xyzx                      // normal
  44: mul r7.xyz, r2.wwww, r7.xyzx                      // 应用法线贴图的副切线分量强度（来自r2.w）
  45: mad r7.xyz, r2.zzzz, r8.xyzx, r7.xyzx                 //  
  46: mad r7.xyz, r3.wwww, r9.xyzx, r7.xyzx                 // 切线空间转为世界空间法线
  47: dp3 r2.z, r7.xyzx, r7.xyzx
  48: rsq r2.z, r2.z
  49: mul r7.xyz, r2.zzzz, r7.xyzx                          // normalize(normalTWS)
  50: mad r2.z, cb5[14].w, l(2.0000), l(-1.0000)     // 双面材质控制反转
  51: movc r2.z, v11.x, l(1.0000), r2.z             // 考虑isfrontface
  52: mul r8.xyz, r2.zzzz, r7.xyzx              // 反转法线 normalTWS
  53: mul r5.xyz, r2.zzzz, r5.xyzx              // // 反转法线 normalWS        //会在辅助光源中被用到
  54: ftou r9.xy, v9.xyxx                     // 
  55: add r2.w, -cb0[91].x, l(1.0000)
  56: mad r2.w, cb0[171].w, r2.w, cb0[91].x         // lerp(cb0[91].x, 1, cb0[171].w)
  57: mul r2.w, r2.w, cb0[89].x                     // lerp(cb0[91].x, 1, cb0[171].w) *  cb0[89].x    // ambeintIntenisty
  58: lt r3.w, cb0[161].y, l(0.5000)                // 烘焙光照
{
  59: if_nz r3.w
  60:   add r10.xyz, v1.xyzx, -cb0[175].xyzx         //   positionWS - volumeOrigin
  61:   max r3.w, abs(r10.y), abs(r10.x)
  62:   max r3.w, abs(r10.z), r3.w
  63:   add r4.w, r3.w, l(-896.0000)           // 896的范围类不渐变， 896之外渐变体积采样结果和固定环境
  64:   mul_sat r4.w, r4.w, l(0.0156)             // / 64
  65:   lt r6.w, l(0), cb0[175].w    // 判断是否采样3d贴图
  66:   lt r7.w, r4.w, l(1.0000)    // 在范围类
  67:   and r6.w, r6.w, r7.w        
  68:   if_nz r6.w    // 在范围类       
  69:     add r10.xy, r3.wwww, l(-100.0000, -200.0000, 0.0000, 0.0000)     // 更具距离划分精度
  70:     mul_sat r10.xy, r10.xyxx, l(0.0833, 0.0625, 0.0000, 0.0000)
  71:     lt r10.xy, r10.xyxx, l(1.0000, 1.0000, 0.0000, 0.0000)
  72:     movc r10.yz, r10.yyyy, l(0.0000, 0.0020, 1.0000, 0.0000), l(0.0000, 0.0005, 2.0000, 0.0000)
  73:     movc r10.xy, r10.xxxx, l(0.0039, 0.0000, 0.0000, 0.0000), r10.yzyy            // 根据距离计算缩放比例和lod
  74:     mul r10.xzw, r10.xxxx, v1.xxyz      
  75:     frc r10.xzw, r10.xxzw    // 取小数
  76:     sample_l(texture3d)(float,float,float,float) r10.xyzw, r10.xzwx, t3.xyzw, s0, r10.y           // 采样3d贴图   取出体素索引
  77:     mad r10.xyzw, r10.xyzw, l(255.0000, 255.0000, 255.0000, 255.0000), l(0.5000, 0.5000, 0.5000, 0.5000)   // 大格子体素坐标
  78:     round_ni r10.xyzw, r10.xyzw           // // 四舍五入到整数
  79:     lt r3.w, l(0), r10.w   
  80:     if_nz r3.w     // 判断alpha通道获取是否有效
  81:       div r11.xyz, v1.xyzx, r10.wwww      // 世界坐标除以体素尺寸
  82:       frc r11.xyz, r11.xyzx
  83:       mad r11.xyz, r11.xyzx, l(4.0000, 4.0000, 4.0000, 0.0000), l(0.5000, 0.5000, 0.5000, 0.0000)    // 划分5*5*5的体素
  84:       mad r10.xyz, r10.xyzx, l(5.0000, 5.0000, 5.0000, 0.0000), r11.xyzx          // 大个子体素 一个大个子是5*5*5个小个子
  85:       mul r10.xyz, r10.xyzx, cb0[176].xyzx   // 除以分辨率
  86:       sample_l(texture3d)(float,float,float,float) r11.xyz, r10.xyzx, t4.xyzw, s1, l(0)     // 采样烘焙光照 rgb分别的 强度
  87:       mul r10.w, r10.z, l(0.3333)     // 缩放， 覆盖更大的距离
  88:       sample_l(texture3d)(float,float,float,float) r12.xyz, r10.xywx, t5.xyzw, s1, l(0)         
  89:       mad r13.xyz, r10.xyzx, l(1.0000, 1.0000, 0.3333, 0.0000), l(0.0000, 0.0000, 0.3333, 0.0000)
  90:       sample_l(texture3d)(float,float,float,float) r13.xyz, r13.xyzx, t5.xyzw, s1, l(0)
  91:       mad r10.xyz, r10.xyzx, l(1.0000, 1.0000, 0.3333, 0.0000), l(0.0000, 0.0000, 0.6667, 0.0000)
  92:       sample_l(texture3d)(float,float,float,float) r10.xyz, r10.xyzx, t5.xyzw, s1, l(0)
  93:       mad r12.xyz, r12.xyzx, l(4.0000, 4.0000, 4.0000, 0.0000), l(-2.0000, -2.0000, -2.0000, 0.0000)   // sh的取值范围变换  - 2 到 2    
  94:       mul r12.xyz, r11.xxxx, r12.xyzx                                             // 
  95:       mad r13.xyz, r13.xyzx, l(4.0000, 4.0000, 4.0000, 0.0000), l(-2.0000, -2.0000, -2.0000, 0.0000)
  96:       mul r13.xyz, r11.yyyy, r13.xyzx
  97:       mad r10.xyz, r10.xyzx, l(4.0000, 4.0000, 4.0000, 0.0000), l(-2.0000, -2.0000, -2.0000, 0.0000)
  98:       mul r10.xyz, r10.xyzx, r11.zzzz
  99:       mov r12.w, r11.x
 100:       add r14.xyzw, -r12.xyzw, cb0[178].xyzw
 101:       mad r12.xyzw, r4.wwww, r14.xyzw, r12.xyzw    // 是否渐变
 102:       mov r13.w, r11.y
 103:       add r14.xyzw, -r13.xyzw, cb0[179].xyzw
 104:       mad r13.xyzw, r4.wwww, r14.xyzw, r13.xyzw
 105:       mov r10.w, r11.z
 106:       add r11.xyzw, -r10.xyzw, cb0[180].xyzw
 107:       mad r10.xyzw, r4.wwww, r11.xyzw, r10.xyzw
 108:     else
 109:       mov r12.xyzw, cb0[178].xyzw
 110:       mov r13.xyzw, cb0[179].xyzw
 111:       mov r10.xyzw, cb0[180].xyzw
 112:     endif
 113:   else
 114:     mov r12.xyzw, cb0[178].xyzw
 115:     mov r13.xyzw, cb0[179].xyzw
 116:     mov r10.xyzw, cb0[180].xyzw
 117:   endif
 118:   mov r8.w, l(1.0000)
 119:   dp4 r11.x, r12.xyzw, r8.xyzw     // normalTWS
 120:   dp4 r11.y, r13.xyzw, r8.xyzw
 121:   dp4 r11.z, r10.xyzw, r8.xyzw        
 122:   max r11.xyz, r11.xyzx, l(0, 0, 0, 0)  //SHEvalLinearL0L1   // shColor
 123:   mul r14.xyz, r2.wwww, r11.xyzx          // shColor * r2.w    originSHColor
 124:   mul r15.xyz, r13.xyzx, l(0.7152, 0.7152, 0.7152, 0.0000)
 125:   mad r15.xyz, r12.xyzx, l(0.2126, 0.2126, 0.2126, 0.0000), r15.xyzx
 126:   mad r15.xyz, r10.xyzx, l(0.0722, 0.0722, 0.0722, 0.0000), r15.xyzx        // dominantDir
 127:   dp3 r3.w, r15.xyzx, r15.xyzx
 128:   max r3.w, r3.w, l(0.0000)
 129:   rsq r3.w, r3.w
 130:   mul r15.xyz, r3.wwww, r15.xyzx        // dominantSHDir
 131:   mov r15.y, abs(r15.y)               // 限制y
 132:   mov r15.w, l(1.0000)              // dominantSHDir
 133:   dp4 r12.x, r12.xyzw, r15.xyzw
 134:   dp4 r12.y, r13.xyzw, r15.xyzw
 135:   dp4 r12.z, r10.xyzw, r15.xyzw
 136:   max r10.xyz, r12.xyzx, l(0, 0, 0, 0)     // SHDominantColor
 137:   max r3.w, r10.y, r10.x
 138:   max r3.w, r10.z, r3.w
 139:   mul r3.w, r2.w, r3.w                    // SHDominantIntensity
 140:   ge r4.w, r14.y, r14.z                       //  RGBtoHCV(in float3 RGB) begin    //https://www.chilliant.com/rgb2hsv.html  shColor
 141:   and r4.w, r4.w, l(1.0000)
 142:   mov r10.xy, r14.zyzz
 143:   mov r10.zw, l(0.0000, 0.0000, -1.0000, 0.6667)                  // 
 144:   mad r11.xy, r11.yzyy, r2.wwww, -r10.xyxx                  // shColor.yz - shColor.zy                     
 145:   mov r11.zw, l(0.0000, 0.0000, 1.0000, -1.0000)
 146:   mad r10.xyzw, r4.wwww, r11.xyzw, r10.xyzw                       // (RGB.g < RGB.b) ? float4(RGB.bg, -1.0, 2.0/3.0) : float4(RGB.gb, 0.0, -1.0/3.0);
 147:   ge r4.w, r14.x, r10.x                                           // (RGB.r < P.x)
 148:   and r4.w, r4.w, l(1.0000)
 149:   mov r11.xyz, r10.xywx
 150:   mov r11.w, r14.x
 151:   mov r10.xyw, r11.wywx
 152:   add r10.xyzw, -r11.xyzw, r10.xyzw
 153:   mad r10.xyzw, r4.wwww, r10.xyzw, r11.xyzw         // (RGB.r < P.x) ? float4(P.xyw, RGB.r) : float4(RGB.r, P.yzx);
 154:   min r4.w, r10.y, r10.w
 155:   add r4.w, -r4.w, r10.x                                  // float C = Q.x - min(Q.w, Q.y);     chroma     r10.x value
 156:   add r6.w, -r10.y, r10.w
 157:   mad r7.w, r4.w, l(6.0000), l(0.0001)
 158:   div r6.w, r6.w, r7.w
 159:   add r6.w, r6.w, r10.z                           // abs((Q.w - Q.y) / (6 * C + Epsilon) + Q.z);                   Hue         RGBtoHCV(in float3 RGB) end
 160:   add r7.w, r10.x, l(0.0001)                                          // value + 0.0001
 161:   div r4.w, r4.w, r7.w                                                // chroma / (value + 0.0001)    // RGBtoHSV(in float3 RGB)  saturation
 162:   frc r6.w, abs(r6.w)                                                     // frac(abs(Hue))
 163:   add r11.xyzw, r6.wwww, l(-0.5000, 1.0000, 0.6667, 0.3333)        //  frac(abs(Hue)) + float4(-0.5000, 1.0000, 0.6667, 0.3333)      c.xxx + K.xyz                    //可以看出颜射调整没改hue
 164:   add r6.w, abs(r11.x), l(-0.4500)                                // abs(frac(abs(Hue)) - 0.5) - 0.45
 165:   mul_sat r6.w, r6.w, l(-10.0000)                                 // saturate((abs(frac(abs(Hue)) - 0.5) - 0.45) * 10)  // hue到终点的距离 大于0.45的边缘部分
 166:   mad r7.w, r6.w, l(-2.0000), l(3.0000)
 167:   mul r6.w, r6.w, r6.w
 168:   mul r6.w, r6.w, r7.w                                 // （3 - 2 * r6.w）*  r6.w * r6.w   smoothstep(0, 1, hue)
 169:   mad r6.w, r6.w, l(-0.3500), l(0.7000)               // 0.7 - 0.35 * hue                  0.35 到 0.7
 170:   mov_sat r10.x, r10.x
 171:   mul r6.w, r6.w, r10.x
 172:   min r4.w, r4.w, r6.w                                    // min(hue * value, saturation)           // 修改后的saturation   亮度越高饱和度越高, 色相越接近红色 饱和度越低
 173:   add r6.w, -r4.w, l(2.0000)                          // 2 - saturation
 174:   rcp r6.w, r6.w
 175:   add r6.w, r6.w, r6.w                                // 2 / (2 - saturation)           修改后的value         饱和度越高 亮度越高
 176:   frc r10.xyz, r11.yzwy                                         // HSVTORGB   begin https://github.com/przemyslawzaworski/Unity3D-CG-programming/blob/master/hsv.shader
 177:   mad r10.xyz, r10.xyzx, l(6.0000, 6.0000, 6.0000, 0.0000), l(-3.0000, -3.0000, -3.0000, 0.0000)    frac( c.xxx + K.xyz ) * 6.0 - K.www 
 178:   add_sat r10.xyz, abs(r10.xyzx), l(-1.0000, -1.0000, -1.0000, 0.0000)  // saturate( p - K.xxx )
 179:   add r10.xyz, r10.xyzx, l(-1.0000, -1.0000, -1.0000, 0.0000)
 180:   mad r10.xyz, r4.wwww, r10.xyzx, l(1.0000, 1.0000, 1.0000, 0.0000)    // lerp( K.xxx, saturate( p - K.xxx ), c.y );
 181:   mul r10.xyz, r6.wwww, r10.xyzx                              // HSVTORGB end                      shColor
 182:   mov r4.w, l(1.0000)
 183:   mov r2.w, r3.w                           //SHDominantIntensity            ambeintIntenisty
 184: else
 185:   lt r3.w, l(1.5000), cb0[161].y
 186:   if_nz r3.w
 187:     mul r11.xyz, r8.yyyy, cb0[1].xyzx
 188:     mad r11.xyz, cb0[0].xyzx, r8.xxxx, r11.xyzx
 189:     mad r11.xyz, cb0[2].xyzx, r8.zzzz, r11.xyzx
 190:     dp3 r3.w, r11.xyzx, r11.xyzx
 191:     rsq r3.w, r3.w
 192:     mul r11.xy, r3.wwww, r11.xyxx            // normalTWS 转到view空间
 193:     mad r11.xy, r11.xyxx, l(0.5000, 0.5000, 0.0000, 0.0000), l(0.5000, 0.5000, 0.0000, 0.0000)
 194:     sample_b(texture2d)(float,float,float,float) r11.xyw, r11.xyxx, t14.yzwx, s9, cb0[88].x            // matCap
 195:     ge r3.w, r11.x, r11.y                            // 上面一样的rgb hsv  饱和度调整
 196:     and r3.w, r3.w, l(1.0000)
 197:     mov r12.xy, r11.yxyy
 198:     mov r12.zw, l(0.0000, 0.0000, -1.0000, 0.6667)
 199:     add r13.xy, r11.xyxx, -r12.xyxx
 200:     mov r13.zw, l(0.0000, 0.0000, 1.0000, -1.0000)
 201:     mad r12.xyzw, r3.wwww, r13.xyzw, r12.xyzw
 202:     ge r3.w, r11.w, r12.x
 203:     and r3.w, r3.w, l(1.0000)
 204:     mov r11.xyz, r12.xywx
 205:     mov r12.xyw, r11.wywx
 206:     add r12.xyzw, -r11.xyzw, r12.xyzw
 207:     mad r11.xyzw, r3.wwww, r12.xyzw, r11.xyzw
 208:     min r3.w, r11.y, r11.w
 209:     add r3.w, -r3.w, r11.x
 210:     add r6.w, -r11.y, r11.w
 211:     mad r7.w, r3.w, l(6.0000), l(0.0001)
 212:     div r6.w, r6.w, r7.w
 213:     add r6.w, r6.w, r11.z
 214:     add r7.w, r11.x, l(0.0001)
 215:     div r3.w, r3.w, r7.w
 216:     add r7.w, -r3.w, l(2.0000)
 217:     div r7.w, l(2.0000), r7.w
 218:     add r11.xyz, abs(r6.wwww), l(1.0000, 0.6667, 0.3333, 0.0000)
 219:     frc r11.xyz, r11.xyzx
 220:     mad r11.xyz, r11.xyzx, l(6.0000, 6.0000, 6.0000, 0.0000), l(-3.0000, -3.0000, -3.0000, 0.0000)
 221:     add_sat r11.xyz, abs(r11.xyzx), l(-1.0000, -1.0000, -1.0000, 0.0000)
 222:     add r11.xyz, r11.xyzx, l(-1.0000, -1.0000, -1.0000, 0.0000)
 223:     mad r11.xyz, r3.wwww, r11.xyzx, l(1.0000, 1.0000, 1.0000, 0.0000)
 224:     mul r11.xyz, r7.wwww, r11.xyzx                     // rgb hsv 调整完
 225:     add r3.w, -cb0[162].w, l(1.0000)
 226:     mad r10.xyz, r11.xyzx, cb0[162].wwww, r3.wwww      // lerp(1, shColor, cb0[162].w)       shColor * cb0[162].w + 1 - cb0[162].w
 227:   else
}
 228:     mov r10.xyz, cb0[162].xyzx                            // shColor
 229:   endif
 230:   mov r15.xyz, l(0, 0, 0, 0)                              // dominantSHDir
 231:   mov r14.xyz, l(1.0000, 1.0000, 1.0000, 0.0000)          // originSHColor
 232:   mov r4.w, l(0)                                          // r4.w设置为0   dominantOn
 233: endif
 234: dp3 r3.w, r8.xyzx, cb0[166].xyzx                         // ndotsky      normalTWS
 235: add_sat r3.w, r3.w, cb0[167].x
 236: mad r3.w, r3.w, cb0[167].y, cb0[167].z                    // saturate(ndotsky +  cb0[167].x) * cb0[167].y + cb0[167].z    应用光照强度与偏移：intensity*scale + bias     ndotSky
 237: add r11.xyz, cb5[19].xyzx, cb1[r4.x + 13].xzyx
 238: add r12.xy, -r11.xyxx, cb0[170].ywyy
 239: mad r11.xy, cb0[170].xxxx, r12.xyxx, r11.xyxx           // lerp(cb5[19].xy + cb1[r4.x + 13].xz, cb0[170].yw, cb0[170].x)    //xyControl
 240: add r6.w, -r11.z, l(1.0000)
 241: mad r6.w, cb0[170].x, r6.w, r11.z        // lerp(r11.z, 1, cb0[170].x)    // 距离差
 242: add r7.w, r11.y, -v1.y                    // r11.y - posiotionWS.y           // 高度差
 243: add r7.w, r7.w, l(0.2000)                 // r11.y - posiotionWS.y + 0.2
 244: mul_sat r7.w, r7.w, l(2.8571)                 // saturate(r7.w * 2.8571)
 245: mad r8.w, r7.w, l(-2.0000), l(3.0000)
 246: mul r7.w, r7.w, r7.w
 247: mul r7.w, r7.w, r8.w                              // smoothstep(0, 1, r7.w)
 248: mul r8.w, r6.w, r7.w                                  //  r6.w * smoothstep(0, 1, r7.w)  距离差 和高度差的影响
 249: mad r6.w, r7.w, r6.w, r11.x               //  smoothstep(0, 1, r7.w) * r6.w  + r11.x 
 250: lt r6.w, l(0.0001), r6.w       
 251: if_nz r6.w                                // 是否有下雨的水滴效果
{
 252:   add r6.w, -r1.x, l(1.0000)              //  1 - metallic
 253:   mul r11.yzw, r0.xxyz, r6.wwww                   // (1 - metallic) * baseColor ==  diffuseColor
 254:   dp3 r7.w, r11.yzwy, l(0.2127, 0.7152, 0.0722, 0.0000)   // // 计算亮度  diffuseIntensity
 255:   add r7.w, r7.w, l(-0.3500)      
 256:   mul_sat r7.w, r7.w, l(-4.0000)                  // saturate((diffuseIntensity - 0.35) * -4)            0.35 亮度之内
 257:   mad r10.w, r7.w, l(-2.0000), l(3.0000)
 258:   mul r7.w, r7.w, r7.w
 259:   mul r11.y, r7.w, r10.w                                      // smoothtep(0, 1, saturate((diffuseIntensity - 0.35) * -4))    mask越暗值越大
 260:   mul r12.xyzw, r8.yyzx, l(0.2000, 0.0000, 0.0000, 1.0000)          // normalTWS.y * 0.2           // NorY
 261:   mul r13.xyz, v8.xzyx, l(1.0000, 1.0000, -1.0000, 0.0000)        // positionOS 反转y            // 判断雨点方向
 262:   movc r13.xyz, cb1[r4.x + 4].wwww, r13.xyzx, v8.xyzx             // positionOS 是否反转Y
 263:   mul r16.xyz, r13.xyzx, cb0[170].zzzz                            // positionOS作为uv tilling
 264:   movc r17.xyz, cb1[r4.x + 4].wwww, v7.xzyx, v7.xyzx                  // normalOS 对应positionOS
 265:   add r18.xyz, abs(r17.xyzx), l(-0.2000, -0.2000, -0.2000, 0.0000)    // abs(normalOS)  - 0.2    normalOSUV
 266:   mul r19.xyz, r18.xyzx, r18.xyzx         
 267:   mul r18.xyz, r18.xyzx, r19.xyzx
 268:   max r18.xyz, r18.xyzx, l(0, 0, 0, 0)           // max(0, normalOSUV * normalOSUV * normalOSUV) ==>  normalOSUV
 269:   dp3 r4.x, r18.xyzx, l(1.0000, 1.0000, 1.0000, 0.0000)    // dot(normalOSUV, float3(1,1,1))
 270:   div r18.xyz, r18.xyzx, r4.xxxx            // 归一化 normalOSUV
 271:   sample_b(texture2d)(float,float,float,float) r19.xyzw, r16.xzxx, t8.xyzw, s5, cb0[88].x           // 水点控制图   xy法线 
 272:   sample_b(texture2d)(float,float,float,float) r20.xyzw, r16.xyxx, t8.xyzw, s5, cb0[88].x
 273:   sample_b(texture2d)(float,float,float,float) r21.xyzw, r16.zyzz, t8.xyzw, s5, cb0[88].x         // 三方向采样
 274:   mul r20.xyzw, r18.zzzz, r20.xyzw
 275:   mad r19.xyzw, r19.xyzw, r18.yyyy, r20.xyzw
 276:   mad r18.xyzw, r21.xyzw, r18.xxxx, r19.xyzw                      // 三方向采样根据normalOS混合dropControl
 277:   add r19.xyz, -r18.wwzw, l(0.8000, 0.4500, 1.0000, 0.0000)       // float3(0.8000, 0.4500, 1.0000) - dropControl.wwz
 278:   mad_sat r4.x, r11.x, r6.w, r12.x                   // saturate((1 - metallic) * xyControl.x + NorY)          // dirAffect 越向上 mask初越明显
 279:   add r4.x, -r19.x, r4.x                                  // 
 280:   mul_sat r4.x, r4.x, l(3.3333)                           // saturate((dirAffect - (0.8 - dropControl.w)) * 3.33)
 281:   mad r11.z, r4.x, l(-2.0000), l(3.0000)
 282:   mul r4.x, r4.x, r4.x
 283:   mul r4.x, r4.x, r11.z                      // smoothstep(0, 1, saturate((dirAffect - (0.8 - dropControl.w)) * 3.33))   ==> dirAffect
 284:   mul_sat r6.w, r6.w, r8.w                    // saturate((1 - metallic) * r8.w)  距离差的影响
 285:   add r6.w, -r19.y, r6.w                      // 
 286:   mul_sat r6.w, r6.w, l(1.5385)                   // saturate((saturate((1 - metallic) * r8.w) - (0.45 - dropControl.w)) * 1.5385)   // distanceAffect
 287:   mad r11.z, r6.w, l(-2.0000), l(3.0000)
 288:   mul r6.w, r6.w, r6.w
 289:   mul r6.w, r6.w, r11.z                           // smoothstep(0, 1, distanceAffect)  ==> distanceAffect
 290:   max r4.x, r4.x, r6.w                            // max(dirAffect,  distanceAffect)         // noiseWetness       
 291:   max r6.w, r8.w, r11.x                       //  max(xyControl.x, r8.w)   //  dotD
 292:   add r8.w, r1.x, l(-0.5000)                  // metallic - 0.5
 293:   mul_sat r8.w, r8.w, l(4.0000)               // saturate((metallic - 0.5) * 4)
 294:   mad r11.x, r8.w, l(-2.0000), l(3.0000)
 295:   mul r8.w, r8.w, r8.w
 296:   mul r8.w, r8.w, r11.x                   // smoothstep(0, 1, saturate((metallic - 0.5) * 4))
 297:   add r1.w, -r1.w, l(0.7000)              // 0.7 - r1.w   
 298:   mul_sat r1.w, r1.w, l(-10.0000)                                 // saturate((0.7 - r1.w) * -10)
 299:   mad r11.x, r1.w, l(-2.0000), l(3.0000)
 300:   mul r1.w, r1.w, r1.w                            // smoothstep(0, 1, saturate((0.7 - r1.w) * -10))   r1.w越大 值越大
 301:   mad r11.z, r11.x, r1.w, r8.w                    //    smoothstep(0, 1, saturate((metallic - 0.5) * 4)) + smoothstep(0, 1, saturate((0.7 - r1.w) * -10))  水点区域
 302:   min r11.z, r11.z, l(1.0000)                         // min(r11.z, 1)           waterDot
 303:   mad r17.yw, r18.xxxy, l(0.0000, 2.0000, 0.0000, 2.0000), l(0.0000, -1.0000, 0.0000, -1.0000)    // dropControl.xy    dotN
 304:   mad r11.w, r11.z, r6.w, -r19.z              //  waterDot * dotD - dropControl.z                   
 305:   mul_sat r11.w, r11.w, l(10.0000)            // saturate((waterDot * dotD - dropControl.z) * 10)
 306:   mad r12.x, r11.w, l(-2.0000), l(3.0000)
 307:   mul r11.w, r11.w, r11.w
 308:   mul r11.w, r11.w, r12.x                    // smoothstep(0, 1, saturate(waterDot * dotD - dropControl.z))    waterDotAffect
 309:   mul r12.x, cb0[82].x, cb0[170].z             
 310:   mul r18.y, r12.x, l(0.7500)                 // cb0[82].x * cb0[170].z * 0.75       // 水流速度   flowSpeed
 311:   dp2 r12.x, r17.xzxx, r17.xzxx
 312:   max r12.x, r12.x, l(0.0000)
 313:   rsq r12.x, r12.x
 314:   mul r17.xz, r12.xxxx, r17.xxzx                      // normalize(normalOS.xz)
 315:   add r17.xz, abs(r17.xxzx), l(-0.2000, 0.0000, -0.2000, 0.0000)   // abs(normalize(ormalOS.xz))  - 0.2   // normalOSXZ
 316:   mul r18.zw, r17.xxxz, r17.xxxz
 317:   mul r17.xz, r17.xxzx, r18.zzwz
 318:   max r17.xz, r17.xxzx, l(0, 0, 0, 0)     //  max(0, normalOSXZ * normalOSXZ * normalOSXZ)
 319:   dp2 r12.x, r17.xzxx, l(1.0000, 1.0000, 0.0000, 0.0000)
 320:   div r17.xz, r17.xxzx, r12.xxxx      // 归一化 normalOSXZ
 321:   sample_b(texture2d)(float,float,float,float) r19.xyz, r16.xyxx, t9.xyzw, s5, cb0[88].x    
 322:   sample_b(texture2d)(float,float,float,float) r16.xyz, r16.zyzz, t9.xyzw, s5, cb0[88].x          // 水流法线
 323:   mov r18.x, l(0)
 324:   mad r13.xyzw, r13.xyzy, cb0[170].zzzz, r18.xyxy          // positionOS.xy * cb0[170].z + flowSpeed   posOff
 325:   sample_b(texture2d)(float,float,float,float) r12.x, r13.xyxx, t9.wxyz, s5, cb0[88].x            // flowMask1
 326:   sample_b(texture2d)(float,float,float,float) r13.x, r13.zwzz, t9.wxyz, s5, cb0[88].x       // flowMask2
 327:   mul r13.yzw, r17.xxxx, r16.xxyz                 // 
 328:   mad r13.yzw, r19.xxyz, r17.zzzz, r13.yyzw       // 两个方向混合下水流法线 flowN
 329:   mul r13.x, r17.x, r13.x                             // normalOSXZ.x * flowMask2
 330:   mad r12.x, r12.x, r17.z, r13.x              //    normalOSXZ.z * flowMask1 + normalOSXZ.x * flowMask2   2方向遮罩混合  flowMask
 331:   mad r13.xy, r13.yzyy, l(2.0000, 2.0000, 0.0000, 0.0000), l(-1.0000, -1.0000, 0.0000, 0.0000)   // flowN * 2 - 1
 332:   mad r13.xy, r13.xyxx, r12.xxxx, r17.ywyy     // (flowN * 2 - 1) * flowMask + dotN    //水流法线+水点法线
 333:   add r12.x, -r13.w, l(1.0000)            //  1 - flowN.z
 334:   mad r6.w, r11.z, r6.w, -r12.x               // waterDot * dotD - (1 - flowN.z)
 335:   mul_sat r6.w, r6.w, l(10.0000)              // saturate((waterDot * dotD - (1 - flowN.z)) * 10)
 336:   mad r11.z, r6.w, l(-2.0000), l(3.0000)
 337:   mul r6.w, r6.w, r6.w
 338:   mul r6.w, r6.w, r11.z        // smoothstep(0, 1, saturate((waterDot * dotD - (1 - flowN.z)) * 10))   
 339:   max r6.w, r6.w, r11.w        // max(waterDotAffect, smoothstep(0, 1, saturate((waterDot * dotD - (1 - flowN.z)) * 10)) )       // waterdotAff
 340:   mad r12.xyz, -r8.zxyz, l(1.0000, 0.0000, 0.0000, 0.0000), r12.yzwy   // normal(-z, 0, x)
 341:   dp2 r11.z, r12.xzxx, r12.xzxx
 342:   lt r11.w, l(0.0001), r11.z
 343:   rsq r11.z, r11.z
 344:   mul r12.xyz, r11.zzzz, r12.xyzx     // normalize()    xz的normal垂直
 345:   movc r12.xyz, r11.wwww, -r12.xyzx, l(-1.0000, 0.0000, 0.0000, 0.0000)      // perturbN
 346:   mul r16.xyz, r8.zxyz, r12.yzxy
 347:   mad r16.xyz, r8.yzxy, r12.zxyz, -r16.xyzx     // binormalPer
 348:   mad r7.xyz, -r7.xyzx, r2.zzzz, r12.xyzx         // -normalTWS * isfront + perturbN
 349:   mad r7.xyz, r13.xxxx, r7.xyzx, r8.xyzx     //扰动法线 normalTWS + r13.x * perturb  ==> pertrub1
 350:   add r12.xyz, -r7.xyzx, r16.xyzx                     // binormalPer - pertrub1
 351:   mad r7.xyz, r13.yyyy, r12.xyzx, r7.xyzx      //(binormalPer - pertrub1) * r13.y + pertrub1       // 相当于normalTWS往 往两个方向偏移 perturbNormal
 352:   dp3 r2.z, r7.xyzx, r7.xyzx
 353:   rsq r2.z, r2.z 
 354:   min r11.z, r2.x, l(0.0500)        // min(r2.x, 0.05)            //  min(r2.x, 0.05)      wet的光滑
 355:   add r11.w, -r2.x, r11.z             // 
 356:   mad r11.w, r6.w, r11.w, r2.x        // lerp(r2.x, min(r2.x, 0.05), waterdotAff)   //相当于湿润影响光滑
 357:   mad r7.xyz, r7.xyzx, r2.zzzz, -r8.xyzx      // perturbNormal - normalTWS
 358:   mad r7.xyz, r6.wwww, r7.xyzx, r8.xyzx   // lerp(normalTWS, perturbNormal, waterdotAff)  // 越湿润越采用偏移了的法线
 359:   dp3 r2.z, r7.xyzx, r7.xyzx
 360:   rsq r2.z, r2.z
 361:   mul r7.xyz, r2.zzzz, r7.xyzx         // normalize(perturbNormal)
 362:   dp3 r2.z, r0.xyzx, l(0.2127, 0.7152, 0.0722, 0.0000)         // dot(baseColor, float4(0.2127, 0.7152, 0.0722))    bIntensity
 363:   add r2.z, r2.z, l(-0.7000)                                          // bIntensity - 0.7
 364:   mul_sat r2.z, r2.z, l(-2.5000)                                  // saturate((bIntensity - 0.7) * -2.5)
 365:   mad r12.x, r2.z, l(-2.0000), l(3.0000)
 366:   mul r2.z, r2.z, r2.z
 367:   mul r2.z, r2.z, r12.x                                   // smoothstep(0, 1, saturate((bIntensity - 0.7) * -2.5))   亮度越低 越大
 368:   mad r2.z, r2.z, l(0.5000), l(1.0000)      // smoothstep(0, 1, saturate((bIntensity - 0.7) * -2.5)) * 0.5 + 1     ==> adjustIntesity
 369:   mul r8.w, r8.w, r6.w                        // smoothstep(0, 1, saturate((metallic - 0.5) * 4)) * waterdotAff    //相当于只印象mask区域
 370:   mad r12.xyz, r0.xyzx, r2.zzzz, -r0.xyzx        // 
 371:   mad r12.xyz, r8.wwww, r12.xyzx, r0.xyzx      //lerp(baseColor, baseColor * adjustIntesity,  smoothstep(0, 1, saturate((metallic - 0.5) * 4)) * waterdotAff)   // baseColorM
 372:   mad r2.z, -r10.w, r7.w, l(1.0000)               //  -smoothtep(0, 1, saturate((diffuseIntensity - 0.35) * -4)) + 1
 373:   mul r2.z, r2.z, r4.x                            // （-smoothtep(0, 1, saturate((diffuseIntensity - 0.35) * -4)) + 1） * noiseWetness   对于diffuseIntensity小的越大
 374:   mad r1.w, -r11.x, r1.w, l(1.0000)               // -smoothstep(0, 1, saturate((0.7 - r1.w) * -10)) + 1
 375:   mul r1.w, r1.w, r2.z                            // (-smoothstep(0, 1, saturate((0.7 - r1.w) * -10)) + 1) * (-smoothtep(0, 1, saturate((diffuseIntensity - 0.35) * -4)) + 1） * noiseWetness
 376:   mad r1.w, r1.w, l(-0.5000), l(1.0000)    // 1 - 0.5 * ( smoothstep(0, 1, saturate((0.7 - r1.w) * -10)) + 1) * smoothtep(0, 1, saturate((diffuseIntensity - 0.35) * -4)) + 1） * noiseWetness
 377:   mul r0.xyz, r1.wwww, r12.xyzx       // baseColorM * r1.w         
 378:   mul r3.xyz, r1.wwww, r3.xyzx        // shadowBaseColor * r1.w
 379:   mul r1.w, r11.y, r4.x               // smoothtep(0, 1, saturate((diffuseIntensity - 0.35) * -4)) * noiseWetness
 380:   mad r1.w, -r1.w, l(0.2000), r11.w   // lerp(r2.x, min(r2.x, 0.05), waterdotAff) -  0.2 *  r1.w 相当于湿润影响光滑
 381:   min r2.z, r11.w, l(0.2000)     //  min(lerp(r2.x, min(r2.x, 0.05), waterdotAff),  0.2)
 382:   max r2.x, r1.w, r2.z    // max(r2.z, r1.w)相当于湿润影响光滑
}
 383: else
 384:   mov r7.xyz, r8.xyzx   // 法线没变
 385:   mov r6.w, l(0)          // wetFactor
 386:   mov r11.z, l(0.0100)    // wet的roungh                 ==> wetRoughness
 387: endif
 388: mul r1.w, r1.y, l(0.0400)                                 // pbrParam.y * 0.04
 389: mad r2.z, -r1.x, l(0.9600), l(0.9600)                     // 0.96 - metallic * 0.96
 390: mul r11.xyw, r0.xyxz, r2.zzzz                                             // (0.96 - metallic * 0.96) * baseColor              diffuseColor
 391: mad r12.xyz, -r1.yyyy, l(0.0400, 0.0400, 0.0400, 0.0000), r0.xyzx         // baseColor - pbrParam.y * 0.04
 392: mad r12.xyz, r1.xxxx, r12.xyzx, r1.wwww                       // lerp(pbrParam.y * 0.04, baseColor, metallic)            specularColor
 393: mul r3.xyz, r2.zzzz, r3.xyzx                                  // shadowBaseColor * ( 0.96 - metallic * 0.96)        shadowDiffuseColor
 394: mul r1.y, r2.x, r2.x                                          // roughness * roughness         roughnessSqr
 395: max r1.y, r1.y, l(0.0078)                                     // max(roughnessSqr, 0.0078)
 396: mul r1.w, r1.y, r1.y                                          // roughnessSqr * roughnessSqr   roughnessSqrSqr
 397: add r13.xyz, cb0[164].xyzx, cb3[0].xyzx
 398: mad r13.xyz, cb0[161].wwww, r13.xyzx, -cb3[0].xyzx          // lerp(-cb3[0].xyz, cb0[164].xyz, cb0[161].w)         // lightDir              考虑是单独控制人物光照还是场景光
 399: dp2 r4.x, r13.xzxx, r13.xzxx
 400: max r4.x, r4.x, l(0.0000)
 401: rsq r4.x, r4.x
 402: mul r16.xy, r4.xxxx, r13.xzxx                                 // normalize(r13.xz)        // lightXZ
 403: add r17.xyz, cb0[165].xyzx, -cb3[3].xyzx
 404: mad r17.xyz, cb0[165].wwww, r17.xyzx, cb3[3].xyzx            // lerp(cb3[3].xyzx, cb0[165].xyzx, cb0[165].wwww)   // lightCol
 405: add r4.x, -cb3[3].w, l(1.0000)                                        // 
 406: mad r4.x, cb0[171].w, r4.x, cb3[3].w                          // lerp(cb3[3].w, 1, cb0[171].w)
 407: mul r18.xyz, r4.xxxx, r17.xyzx                                // lerp(cb3[3].xyzx, cb0[165].xyzx, cb0[165].wwww) * lerp(cb3[3].w, 1, cb0[171].w)    // lightColor
 408: dp3 r7.w, r18.xyzx, l(0.2127, 0.7152, 0.0722, 0.0000)         // rIntesity
 409: mov r9.z, l(0)
 410: ld_indexable(texture2d)(float,float,float,float) r16.zw, r9.xyzz, t2.zwxy            // screenPos 采样   ShadowTex
 411: ftoi r8.w, cb4[31].x                                                                  // 
 412: ilt r8.w, l(0), r8.w                              // 0 < cb4[31].x
 413: movc r8.w, r8.w, r16.z, cb4[31].z                 // 0 < cb4[31].x ? ShadowTex.x : cb4[31].z      // 是否获取场景阴影
 414: add r8.w, r8.w, l(-1.0000)                        // 
 415: mad r8.w, cb4[30].x, r8.w, l(1.0000)              // lerp(1, shadowTex.x, cb4[30].x)  应用阴影全局强度   sceneShadow
 416: add r9.z, -r8.w, l(1.0000)                        
 417: mad r8.w, cb0[161].z, r9.z, r8.w                  // lerp(sceneShadow, 1,  cb0[161].z)    场景阴影强度    curSceneShadow
 418: dp3 r9.z, r8.xyzx, r13.xyzx                       // dot(normalTWS, lightDir)    ndotlt
 419: dp2 r10.w, cb0[6].xzxx, cb0[6].xzxx               // 
 420: rsq r10.w, r10.w
 421: mul r18.xy, r10.wwww, cb0[6].xzxx                 // normalize(cb0[6].xz)            // 假定cb0[6] camVector
 422: dp2 r10.w, r16.xyxx, r18.xyxx                                                 // dot(r16xy, camVector.xy)    camDotLXZ
 423: mul r18.xyz, r3.xyzx, cb0[160].zzzz                           // shadowDiffuseColor * cb0[160].z    shadowDiffuseColor             cb0[160].z 暗部强度
 424: mul r19.xyz, r18.xyzx, l(0.6500, 0.6500, 0.6500, 0.0000)              // shadowDiffuseColor * cb0[160].z * 0.65     satDiff
 425: dp3 r12.w, r19.xyzx, l(0.2127, 0.7152, 0.0722, 0.0000)                                            // 计算灰度值 satDiffIntensity
 426: mad r19.xyz, r18.xyzx, l(0.6500, 0.6500, 0.6500, 0.0000), -r12.wwww     
 427: mad r19.xyz, r19.xyzx, l(1.2000, 1.2000, 1.2000, 0.0000), r12.wwww        // lerp(satDiffIntensity, satDiff, 1.2)   增强饱和度   _2ndShadowDiffuseColor
 428: dp3 r12.w, r11.xywx, l(0.2127, 0.7152, 0.0722, 0.0000)                // diffIntensity
 429: mad r20.xyz, r0.xyzx, r2.zzzz, -r12.wwww
 430: mad r20.xyz, r20.xyzx, l(1.2000, 1.2000, 1.2000, 0.0000), r12.wwww        // lerp(diffInteisty, diffuseColor, 1.2)  增强饱和度  _2ndDiffuseColor
 431: add r13.w, -abs(cb0[6].y), l(0.7500)                                  // 0.75 - abs(camVector.y)
 432: add_sat r13.w, r13.w, r13.w                                           // saturate((0.75 - abs(camVector.y)) * 2)
 433: mad r14.w, r13.w, l(-2.0000), l(3.0000)                               // 
 434: mul r13.w, r13.w, r13.w
 435: mul r13.w, r13.w, r14.w                                               // smoothstep(0, 1, saturate((0.75 - abs(camVector.y)) * 2))    // yFactor      // 
 436: mad r14.w, r9.z, l(0.5000), l(-1.0000)                            // ndotlt * 0.5 - 1
 437: mad r14.w, -r9.z, r14.w, -r9.z                                    // (1 - ndotlt * 0.5) * ndotlt - ndotlt           // -0.5 * ndotlt * ndotlt                         
 438: mov_sat r10.w, -r10.w                                             // -camDotLXZ
 439: mul r13.w, r13.w, r10.w                                           // yFactor * saturate(-camDotLXZ) 
 440: add r15.w, -cb0[163].w, l(1.0000)                                 // 1 - cb0[163].w
 441: mul r13.w, r13.w, r15.w                                           // (1 - cb0[163].w) * yFactor * saturate(-camDotLXZ);
 442: add r14.w, r14.w, l(0.5000)                                   // 0.5 + r14.w
 443: mad r9.z, r13.w, r14.w, r9.z                                  // ndotlt + (1 - cb0[163].w) * yFactor * saturate(-camDotLXZ) *(0.5 -0.5 * ndotlt * ndotlt)    // 考虑背光部分 考虑相机方向，光照正背对增强
 444: mad r9.z, cb0[164].w, cb0[163].w, r9.z                        // // mad 偏移cb0[164].w 光照ramp偏移，  cb0[163].w 背光控制 lerp(yFactor * saturate(-camDotLXZ) *(0.5 -0.5 * ndotlt * ndotlt), cb0[164].w, cb0[163])
 445: max r9.z, r9.z, l(-1.0000)
 446: min r9.z, r9.z, l(1.0000)                                             // 限制范围
 447: mad r21.x, r9.z, l(0.5000), l(0.5000)                                 //  r9.z * 0.5 + 0.5
 448: mov r21.yw, l(0.0000, 0.5000, 0.0000, 0.5000)
 449: sample_l(texture2d)(float,float,float,float) r22.xyzw, r21.xyxx, t6.xyzw, s3, l(0)         // rampTex
 450: max r9.z, r22.y, r22.x                        // max(rampTex.x, rampTex.y) 
 451: max r9.z, r22.z, r9.z                         // max(max(rampTex.x, rampTex.y), rampTex.z)
 452: min r13.w, r22.y, r22.x
 453: min r13.w, r22.z, r13.w                       // min(min(rampTex.x, rampTex.y), rampTex.z)
 454: add r9.z, r9.z, -r13.w                // max - min          // rampTexRange
 455: add r13.w, cb0[6].y, l(0.2500)        // 
 456: min r23.y, r13.w, l(1.0000)           // min(0.25 + cb0[6].y, 1)
 457: mov r23.xz, cb0[6].xxzx               // camVector
 458: dp3 r13.w, r23.xyzx, r23.xyzx
 459: rsq r13.w, r13.w
 460: mul r23.xyz, r13.wwww, r23.xyzx              // normalize(camVector)
 461: dp3 r13.w, r8.xyzx, r23.xyzx                  // dot(normalTWS, camVector)
 462: mad r21.z, r13.w, l(0.5000), l(0.5000)            // r13.w * 0.5 + 0.5
 463: sample_l(texture2d)(float,float,float,float) r13.w, r21.zwzz, t6.xyzw, s3, l(0)    // camRampTexW 
 464: mul r14.w, r1.z, r16.w                                // AO * ShadowTex.y
 465: mul r16.z, r13.w, r14.w                               // AO * ShadowTex.y * camRampTexW               // camShadowRadiance
 466: mad_sat r17.w, r14.w, r13.w, r22.w                    // saturate(rampTex.w + camShadowRadiance)   // rampRadiance
 467: mad r21.xyz, r3.xyzx, cb0[160].zzzz, -r19.xyzx
 468: mad r19.xyz, r17.wwww, r21.xyzx, r19.xyzx             // lerp(_2ndShadowDiffuseColor, shadowDiffuseColor, rampRadiance)   //  combineShadowDiffuseColor
 469: min r17.w, r1.z, r16.w                                // min(AO, ShadowTex.y)
 470: min r18.w, r22.w, r17.w                               // min(rampTex.w, min(AO, ShadowTex.y))  ==> rampShadowRadiance
 471: min r19.w, cb0[161].y, l(1.0000)               // cb0[161].y  0  为烘焙
 472: mul r19.w, r18.w, r19.w                                    // rampShadowRadiance * min(cb0[161].y, l(1.0000))    // 
 473: add r21.xyz, -r10.xyzx, l(1.0000, 1.0000, 1.0000, 0.0000)
 474: mad r21.xyz, r19.wwww, r21.xyzx, r10.xyzx          // lerp(shColor, 1,  rampShadowRadiance * min(cb0[161].y, l(1.0000)))    shCol       ambientCol //不开启体积光照贴图通过阴影参数控制
 475: mul r21.xyz, r3.wwww, r21.xyzx                        // ndotSky * ambientCol
 476: mad r23.xyz, r17.xyzx, r4.xxxx, -r7.wwww
 477: mad r23.xyz, r18.wwww, r23.xyzx, r7.wwww               // lerp(rIntesity, lightColor, rampShadowRadiance)    // lightColorM
 478: max r24.xyz, r2.wwww, l(0.0000, 1.2500, 0.5000, 0.0000)    // max(ambeintIntenisty, l(0.0000, 1.2500, 0.5000, 0.0000))
 479: min r24.xyz, r24.xyzx, l(1.5000, 1.7500, 1.5000, 0.0000)  // min(max(ambeintIntenisty, l(0.0000, 1.2500, 0.5000, 0.0000)),  l(1.5000, 1.7500, 1.5000, 0.0000))   ==>  mulIntesity
 480: mul r25.xyz, r21.xyzx, r24.xxxx                  // ndotSky * ambientCol * mulIntesity.x
 481: add r3.w, -cb0[165].w, l(1.0000)                  // 
 482: mad r26.xyz, r17.xyzx, cb0[165].wwww, r3.wwww     // lerp(lightCol, 1, cb0[165].w)    // cb0[165].w 光照颜色选择
 483: mad r23.xyz, r25.xyzx, r26.xyzx, r23.xyzx         //  ndotSky * ambientCol * mulIntesity.x * lerp(lightCol, 1, cb0[165].w) + lightColorM      ==>lightAndAmbientCol
 484: mad r2.w, r2.w, l(0.3500), l(0.6500)              // ambeintIntenisty * 0.35 + 0.65
 485: min r2.w, r2.w, l(1.5000)             // min(1.5, ambeintIntenisty * 0.35 + 0.65)
 486: add r3.w, -r2.w, r24.y                // mulIntesity.y - min(1.5, ambeintIntenisty * 0.35 + 0.65)
 487: mad r2.w, cb0[161].x, r3.w, r2.w        // lerp(min(1.5, ambeintIntenisty * 0.35 + 0.65), mulIntesity.y, cb0[161].x)   //选择强度  mulIntesity1
 488: mul r21.xyz, r21.xyzx, r2.wwww            // ndotSky * ambientCol * mulIntesity1
 489: mul r21.xyz, r21.xyzx, cb0[160].wwww      // ndotSky * ambientCol * mulIntesity1 * cb0[160].w
 490: mad r23.xyz, r23.xyzx, cb0[160].yyyy, -r21.xyzx
 491: mad r21.xyz, r8.wwww, r23.xyzx, r21.xyzx              // lerp(ndotSky * ambientCol * mulIntesity1 * cb0[160].w, lightAndAmbientCol * cb0[160].y, curSceneShadow)    // ambientAndLightCol
 492: mad r23.xyz, r0.xyzx, r2.zzzz, -r19.xyzx              
 493: mad r19.xyz, r18.wwww, r23.xyzx, r19.xyzx                 // lerp(combineShadowDiffuseColor, diffuseColor, rampShadowRadiance)     curDiffuseColor
 494: dp3 r2.w, r19.xyzx, l(0.2127, 0.7152, 0.0722, 0.0000)     // curDiffuseIntensity
 495: add r3.w, -r9.z, l(1.0000)
 496: mad r22.xyz, r22.xyzx, r9.zzzz, r3.wwww                   // lerp(1, rampTex.rgb, rampTexRange)
 497: mul r19.xyz, r19.xyzx, r22.xyzx                           // lerp(1, rampTex.rgb, rampTexRange) * curDiffuseColor        // rampCurDiffuseColor
 498: dp3 r3.w, r19.xyzx, l(0.2127, 0.7152, 0.0722, 0.0000)    // rampCurDiffuseIntensity
 499: max r3.w, r3.w, l(0.0010)
 500: rcp r3.w, r3.w
 501: mul r2.w, r2.w, r3.w                              // curDiffuseIntensity / max(rampCurDiffuseIntensity, 0.001)   // 避免ramp后亮度改变，所以调整下亮度
 502: max r2.w, r2.w, l(0)
 503: min r2.w, r2.w, l(1.5000)                         // clamp(0, 1.5, curDiffuseIntensity / max(rampCurDiffuseIntensity, 0.001))            normCurDiffuseIntensity
 504: mad r20.xyz, -r3.xyzx, cb0[160].zzzz, r20.xyzx    // 
 505: mad r18.xyz, r16.zzzz, r20.xyzx, r18.xyzx         // lerp(shadowDiffuseColor, _2ndDiffuseColor, camShadowRadiance)        diffuseInSceneShadow
 506: mad r19.xyz, r19.xyzx, r2.wwww, -r18.xyzx
 507: mad r18.xyz, r8.wwww, r19.xyzx, r18.xyzx          // lerp(diffuseInSceneShadow, rampCurDiffuseColor * normCurDiffuseIntensity, curSceneShadow)   resultDiffuse       
 508: mul r19.xyz, r18.xyzx, r21.xyzx                   // ambientAndLightCol * resultDiffuse                 // ambientAndLightDiffuse   
 509: mad r2.w, -r14.w, r13.w, r18.w                    //               
 510: mad r2.w, r8.w, r2.w, r16.z                       // lerp(camShadowRadiance, rampShadowRadiance, curSceneShadow)    // combineRadiance
 511: mad r3.w, r2.w, l(0.5000), l(0.5000)              // combineRadiance * 0.5 + 0.5
 512: add r7.w, -cb0[160].z, l(1.0000)                  // 1 - cb0[160].z 
 513: mad r2.w, r2.w, r7.w, cb0[160].z                  // lerp(cb0[160].z, 1, combineRadiance)
 514: mul r2.w, r2.w, r3.w                              // (combineRadiance * 0.5 + 0.5) * lerp(cb0[160].z, 1, combineRadiance)
 515: mul r20.xyz, r2.wwww, r21.xyzx                    // (combineRadiance * 0.5 + 0.5) * lerp(cb0[160].z, 1, combineRadiance) * ambientAndLightCol            // ambeintAndLightradiance
 516: add r2.w, r13.y, l(-0.5000)                       // lightDir.y - 0.5
 517: mad r21.y, r8.w, r2.w, l(0.5000)                  // lerp(0.5, lightDir.y, curSceneShadow)
 518: mov r21.xz, cb0[6].xxzx                           // camVector
 519: add r21.xyz, r21.xyzx, r21.xyzx                   // 
 520: mad r13.xyz, r13.xyzx, r8.wwww, r21.xyzx          // lightDir * curSceneShadow  + camVector * 2               // shiftLightDir
 521: dp3 r2.w, r13.xyzx, r13.xyzx
 522: max r2.w, r2.w, l(0.0000)
 523: rsq r2.w, r2.w
 524: mad r13.xyz, r13.xyzx, r2.wwww, r6.xyzx           // normalize(halfVector) + viewDirWS       ==> halfDir
 525: dp3 r2.w, r13.xyzx, r13.xyzx                      // 
 526: max r2.w, r2.w, l(0.0000)
 527: rsq r2.w, r2.w
 528: mul r13.xyz, r2.wwww, r13.xyzx                    // normalize(halfDir)
 529: dp3_sat r21.x, r7.xyzx, r6.xyzx                   // saturate(ndotv)
 530: dp3 r2.w, r7.xyzx, r13.xyzx                       // ndoth
 531: mad r3.w, r2.w, r1.w, -r2.w                       // roughnessSqrSqr * ndoth - ndoth   // D_GGX(float Roughness, float NoH)
 532: mad r2.w, r3.w, r2.w, l(1.0000)                   // (roughnessSqrSqr * ndoth - ndoth) * ndoth + 1
 533: mul r2.w, r2.w, r2.w
 534: ne r3.w, r1.w, r2.w
 535: div r1.w, r1.w, r2.w                              // D_GGX(float Roughness, float NoH)
 536: movc r1.w, r3.w, r1.w, l(1.0000)                  //  fullroughness 为1           D_GGX  end
 537: mad r2.w, r21.x, l(2.0000), r1.y                  // ndotv*2 + roughnessSqr
 538: add r2.w, r2.w, l(0.0001)
 539: rcp r2.w, r2.w
 540: mul r2.w, r1.w, r2.w                              // D_GGX / (ndotv*2 + roughnessSqr + 0.0001)           ggxTerm
 541: mad r3.w, r1.y, r1.y, l(0.0001)                     // roughnessSqr * roughnessSqr + 0.0001  
 542: div r3.w, l(1.0000, 1.0000, 1.0000, 1.0000), r3.w        //  1 / (roughnessSqr * roughnessSqr + 0.0001  )       ggxMax    相当于法线关照同向的情况
 543: div r1.w, r1.w, r3.w                          // D_GGX  / (1 / (roughnessSqr * roughnessSqr + 0.0001  ))       最大ggx值做归一化 D_GGX / ggxMax
 544: mul r13.x, r21.x, r21.x                       // ndotv * ndotv
 545: mad r3.w, r21.x, r21.x, -r1.w
 546: mad r22.x, cb5[2].y, r3.w, r1.w                   // lerp(D_GGX / ggxMax, ndotv * ndotv, cb5[2].y)       
 547: mul r22.y, r2.y, r2.x                             // (1 - metallic) * roughness
 548: sample_l(texture2d)(float,float,float,float) r22.xyz, r22.xyxx, t7.xyzw, s4, l(0)             // specularStylizedLUT         uv u是 越粗糙越非金属就往黄色偏移 v 是ggx归一化比值 途中可以相当于中心变红边缘偏青
 549: mul r23.xyz, r12.xyzx, r22.xyzx                                       // specularColor * ggxStylizedLUT           styleSpecularColor
 550: mad r22.xyz, r12.xyzx, r22.xyzx, -r12.xyzx
 551: mad r12.xyz, cb5[2].yyyy, r22.xyzx, r12.xyzx            // lerp(specularColor, specularColor * specularStylizedLUT, cb5[2].y)     // curSpecularColor
 552: mad r1.w, r2.w, l(0.5000), l(-0.0001)
 553: max r1.w, r1.w, l(0)
 554: min r1.w, r1.w, l(20.0000)
 555: mul r22.xyz, r23.xyzx, r1.wwww                            // specularColor * specularStylizedLUT * min(20, max(ggxTerm * 0.5 - 0.0001, 0))  ==>  specularTerm
 556: mul r20.xyz, r20.xyzx, r22.xyzx                           // ambeintAndLightradiance * specularTerm       // ambientAndLightSpecular
 557: add r1.w, -cb5[9].w, l(1.0000)                            // 1 - cb5[9].w
 558: mad r1.w, r0.w, cb5[9].w, r1.w                            // lerp(1, baseColor.w, cb5[9].w)
 559: mad r19.xyz, r19.xyzx, r1.wwww, r20.xyzx                  // ambientAndLightDiffuse * lerp(1, baseColor.w, cb5[9].w) + ambientAndLightSpecular            // ambientAndLightResultCol
 560: dp3 r2.y, r19.xyzx, l(0.2127, 0.7152, 0.0722, 0.0000)     // ambientAndLightResultColIntensity
 561: add r2.w, r2.y, l(-0.5000)                                // ambientAndLightResultColIntensity - 0.5
 562: max r2.w, r2.w, l(0)                                      
 563: min r2.w, r2.w, l(0.5000)                                 // min(max(ambientAndLightResultColIntensity, 0), 0.5)  ambientAndLightIntensity
 564: mad r2.w, r2.w, r2.w, l(1.0000)                           // ambientAndLightIntensity * ambientAndLightIntensity + 1
 565: add r19.xyz, -r2.yyyy, r19.xyzx                           
 566: mad r19.xyz, r2.wwww, r19.xyzx, r2.yyyy                   // lerp(ambientAndLightResultColIntensity, ambientAndLightResultCol, ambientAndLightIntensity * ambientAndLightIntensity + 1)  //0.5以上的亮度 做一个饱和度调整 ambientAndLightResultCol
 567: lt r2.y, l(0.0100), cb0[168].w                            // 0.01 < cb0[168].w    rimLightOn
 568: mul r20.xyz, cb0[6].zxyz, cb0[169].yzxy
 569: mad r20.xyz, cb0[6].yzxy, cb0[169].zxyz, -r20.xyzx    // cross(camVector, cb0[169].xyz)
 570: dp3 r2.w, r20.xyzx, r20.xyzx                          // 
 571: max r2.w, r2.w, l(0.0000)
 572: rsq r2.w, r2.w
 573: mul r20.xyz, r2.wwww, r20.xyzx                        // normalize(cross(camVector, cb0[169].xyz))    camRimDir
 574: dp3 r2.w, r6.xyzx, r8.xyzx                                                        // ndotv
 575: add r22.xy, -abs(r2.wwww), l(1.0000, 0.4000, 0.0000, 0.0000)                      // (1, 0.4) - abs(ndotv)             // reverseNdotV
 576: mad r22.zw, cb0[167].wwww, l(0.0000, 0.0000, -0.6000, -0.4000), l(0.0000, 0.0000, 0.8000, 0.9000)         // (0.8, 0.9) - cb0[167].w * (0.6, 0.4)
 577: add r2.w, -r22.z, r22.w                                                       // r22.w - r22.z
 578: add r3.w, -r22.z, r22.x                                                       // reverseNdotV.x - r22.z
 579: div r2.w, l(1.0000, 1.0000, 1.0000, 1.0000), r2.w                             // 
 580: mul_sat r2.w, r2.w, r3.w                                                      // saturate((reverseNdotV.x - r22.z) / (r22.w - r22.z))
 581: mad r3.w, r2.w, l(-2.0000), l(3.0000)
 582: mul r2.w, r2.w, r2.w
 583: mul r2.w, r2.w, r3.w                                                      // smoothstep(0, 1, saturate((reverseNdotV.x - r22.z) / (r22.w - r22.z)))   rimFactor
 584: mul r24.xyw, r2.wwww, cb0[168].xyxz                                       // cb0[168].xyz * rimFactor
 585: mul r24.xyw, r24.xyxw, cb0[168].wwww                                      // cb0[168].wwww * cb0[168].xyz * rimFactor          // rimlight
 586: dp2 r2.w, r4.yzyy, r20.xzxx                               // dot(objectDir, camRimDir.xz)
 587: add_sat r2.w, r2.w, l(1.0000)                             // saturate(dot(objectDir, camRimDir.xz) + 1)   camRimFactor
 588: min r1.z, r1.z, r2.w                                      // min(AO, camRimFactor)
 589: min r1.z, r16.w, r1.z                                     // min(min(AO, camRimFactor), shadowTex.y)      rimShadow
 590: mul r24.xyw, r1.zzzz, r24.xyxw                            // rimlight * rimShadow
 591: dp3_sat r1.z, r20.xyzx, r8.xyzx                           // saturate(dot(camRimDir, normalTWS))    ndotCamRimDir
 592: mad r20.xyz, r0.xyzx, r2.zzzz, l(-0.2500, -0.2500, -0.2500, 0.0000)       // 
 593: mad r20.xyz, cb0[166].wwww, r20.xyzx, l(0.2500, 0.2500, 0.2500, 0.0000)  // lerp(0.25, diffuseColor, cb0[166].w)
 594: mul r20.xyz, r1.zzzz, r20.xyzx                            // ndotCamRimDir * lerp(0.25, diffuseColor, cb0[166].w)
 595: mul r20.xyz, r20.xyzx, r24.xywx                           // rimlight * rimShadow * ndotCamRimDir * lerp(0.25, diffuseColor, cb0[166].w)       rimLightColor 
 596: and r20.xyz, r2.yyyy, r20.xyzx                            // rimLightOn && rimLightColor
 597: dp2 r1.z, r16.xyxx, r8.xzxx                               // ndotlXZ
 598: dp3 r2.y, r15.xyzx, r8.xyzx                               // ndotDominantSHDir     dominantSHDir
 599: mul r2.w, r4.w, r2.y                                      // dominantOn * ndotDominantSHDir           ndotDominant
 600: mad r3.w, r1.z, l(0.5000), l(-1.0000)                     // ndotlXZ * 0.5 - 1
 601: mad r1.z, -r1.z, r3.w, l(0.5000)                          // 0.5 - (ndotlXZ * 0.5 - 1) * ndotlXZ
 602: mad r1.z, -r2.y, r4.w, r1.z                               
 603: mad_sat r1.z, r8.w, r1.z, r2.w                            // saturate(lerp(ndotDominant, 0.5 - (ndotlXZ * 0.5 - 1) * ndotlXZ, curSceneShadow)   // gEnvRadiance
 604: mul_sat r2.y, r22.y, l(5.0000)                            // saturate(reverseNdotV.y * 5)
 605: mad r2.w, r2.y, l(-2.0000), l(3.0000)
 606: mul r2.y, r2.y, r2.y
 607: mul r2.y, r2.y, r2.w                                      // smoothstep(0, 1, saturate(reverseNdotV.y * 5))      reverseRimContrl
 608: add r2.w, -r8.w, l(1.0000)                                //  1 - curSceneShadow
 609: mad r3.w, r10.w, r8.w, r2.w                               // lerp(1, -camDotLXZ, curSceneShadow)
 610: mul r3.w, r15.w, r3.w                                     // (1 - cb0[163].w) * lerp(1, -camDotLXZ,curSceneShadow)  // backContorl // 背光控制
 611: add r4.w, r12.w, l(-0.1000)                               // diffIntensity - 0.1
 612: mul_sat r4.w, r4.w, l(-16.6667)                           // saturate((diffIntensity - 0.1) * -16.6667)   //小于0.1的区域
 613: mad r7.w, r4.w, l(-2.0000), l(3.0000)
 614: mul r4.w, r4.w, r4.w
 615: mul r4.w, r4.w, r7.w                              // smoothstep(0, 1, saturate((diffIntensity - 0.1) * -16.6667)) // lowDiffIntensityFactor
 616: mad r4.w, r4.w, r8.w, r2.w                        // lerp(1, lowDiffIntensityFactor, curSceneShadow)     
 617: max r7.w, r14.y, r14.x                            // 
 618: max r7.w, r14.z, r7.w                             // max(originSHColor.x, originSHColor.y, originSHColor.z)  originSHColorMaxComp
 619: mul r7.w, r7.w, l(0.5000)
 620: max r7.w, r7.w, l(1.0000)                         // max(originSHColorMaxComp * 0.5, 1)
 621: rcp r7.w, r7.w
 622: mul r14.xyz, r7.wwww, r14.xyzx                    // originSHColor / max(originSHColorMaxComp * 0.5, 1)   // normOriginSHColor
 623: mad r15.xyz, r17.xyzx, r4.xxxx, -r14.xyzx     
 624: mad r14.xyz, r8.wwww, r15.xyzx, r14.xyzx                      // lerp(normOriginSHColor, lightColor, curSceneShadow)      gEnvColor
 625: max r15.xyz, r11.xywx, l(0.1500, 0.1500, 0.1500, 0.0000)      // diffuseColor * 0.15
 626: mul r14.xyz, r1.zzzz, r14.xyzx                        // gEnvColor * gEnvRadiance
 627: mul r14.xyz, r3.wwww, r14.xyzx                        // gEnvColor * gEnvRadiance * backContorl
 628: mul r14.xyz, r2.yyyy, r14.xyzx                        // gEnvColor * gEnvRadiance * backContorl * reverseRimContrl
 629: mul r14.xyz, r17.wwww, r14.xyzx                       // gEnvColor * gEnvRadiance * backContorl * reverseRimContrl * min(AO, ShadowTex.y)
 630: mul r14.xyz, r4.wwww, r14.xyzx                        // gEnvColor * gEnvRadiance * backContorl * reverseRimContrl * min(AO, ShadowTex.y) * lerp(1, lowDiffIntensityFactor, curSceneShadow)      gEnvColorR
 631: mad r14.xyz, r14.xyzx, r15.xyzx, r20.xyzx             // diffuseColor * 0.15 * gEnvColorR + rimLightColor               // gEnvDiffuseAndRim
 632: add r1.z, -r2.x, r11.z                                //  
 633: mad r1.z, r6.w, r1.z, r2.x                            // lerp(roughness, wetRoughness, wetFactor)    roughness
 634: mul r15.y, r1.z, r1.z                                 // roughness * roughness       // specularGGXReflectanceApprox(float3 specularF0, float alpha, float NdotV)         见https://github.com/boksajak/brdf/blob/master/brdf.h
 635: mul r13.z, r21.x, r13.x                               // ndotv * ndotv * ndotv           r21.x ndotv
 636: mul r2.y, r15.y, r15.y                                // roughness^4   
 637: mul r15.z, r15.y, r2.y                                // roughness^6
 638: mov r21.yzw, l(0.0000, 0.0365, 9.0632, 0.9904)                // 
 639: dp2 r16.x, l(3.3271, 1.0000, 0.0000, 0.0000), r21.xyxx        //  dot((3.3271, 1), (ndotv, 0.0365)) 
 640: dp2 r16.y, l(-9.0476, 1.0000, 0.0000, 0.0000), r21.xzxx       // dot(-9.0476, 1), (ndotv, 9.0632))         // shiftNdotv
 641: mov r15.x, l(1.0000)
 642: dp2 r2.y, r16.xyxx, r15.xyxx                                  // dot(shiftNdotv, (1, roughness * roughness))
 643: mov r13.yw, l(0.0000, 9.0440, 0.0000, 1.0000)
 644: dp3 r16.x, l(3.5968, -1.3677, 1.0000, 0.0000), r13.xzwx       // dot((3.5968, -1.3677, 1), (ndotv * ndotv, ndotv * ndotv * ndotv, 1))
 645: dp3 r16.y, l(-16.3174, 1.0000, 9.2295, 0.0000), r13.xyzx      // dot((-16.3174, 1.0000, 9.2295), (ndotv * ndotv, 9.044, ndotv * ndotv * ndotv))
 646: mov r17.x, l(5.5659)
 647: mov r17.yz, r13.xxzx
 648: dp3 r16.z, l(1.0000, 19.7886, -20.2123, 0.0000), r17.xyzx
 649: dp3 r3.w, r16.xyzx, r15.xyzx
 650: div r2.y, r2.y, r3.w
 651: dp2 r16.x, l(-1.2851, 1.0000, 0.0000, 0.0000), r21.xwxx
 652: mov r13.x, l(1.2968)
 653: mov r13.y, r21.x
 654: dp2 r16.y, l(1.0000, -0.7559, 0.0000, 0.0000), r13.xyxx
 655: dp2 r3.w, r16.xyxx, r15.xyxx
 656: dp3 r16.x, l(2.9234, 59.4188, 1.0000, 0.0000), r13.yzwy
 657: mov r13.xw, l(20.3225, 0.0000, 0.0000, 121.5630)
 658: dp3 r16.y, l(1.0000, -27.0302, 222.5920, 0.0000), r13.xyzx
 659: dp3 r16.z, l(626.1300, 316.6270, 1.0000, 0.0000), r13.yzwy
 660: dp3 r4.x, r16.xyzx, r15.xyzx
 661: div r3.w, r3.w, r4.x
 662: mad r13.xyz, r12.xyzx, r2.yyyy, r3.wwww                           //  curSpecularColor * r2.yyyy, r3.wwww          reflectionApprox // specularGGXReflectanceApprox    类似unreal 环境brdf 的分离求和
 663: add r2.y, r2.y, r3.w                                              // r2.y + r3.w  
 664: add r3.w, -r2.y, l(1.0000)                                        // 1 - (r2.y + r3.w)
 665: div r2.y, r3.w, r2.y                                              // (1 - (r2.y + r3.w)) / (r2.y + r3.w)
 666: mul r12.xyz, r12.xyzx, r2.yyyy                                    // curSpecularColor * (1 - (r2.y + r3.w)) / (r2.y + r3.w)
 667: mad r12.xyz, r12.xyzx, r13.xyzx, r13.xyzx                         // reflectionApprox + reflectionApprox * curSpecularColor * (1 - (r2.y + r3.w)) / (r2.y + r3.w)                // iblspcBrdfApporx
 668: dp3 r2.y, -r6.xyzx, r7.xyzx                                       // 
 669: add r2.y, r2.y, r2.y
 670: mad r6.xyz, r7.xyzx, -r2.yyyy, -r6.xyzx                           // reflect(-viewDir, normal)
 671: max r1.z, r1.z, l(0.0010)                                         // max(roughness, 0.001)
 672: log r1.z, r1.z
 673: mad r1.z, -r1.z, l(1.2000), l(1.0000)                             
 674: add r1.z, -r1.z, l(6.0000)                                // mipLevel = 6-(1 - 1.2*log2(roughness))                // 类似ue4 ComputeReflectionCaptureMipFromRoughness
 675: sample_l(texturecube)(float,float,float,float) r6.xyz, r6.xyzx, t13.xyzw, s8, r1.z              // envCube
 676: mul r6.xyz, r12.xyzx, r6.xyzx                                                 // iblspcBrdfApporx * envCube               envSpecluar
 677: mul r1.z, r24.z, cb0[160].w                                           // mulIntesity.z * cb0[160].w    // cb0[160].w  环境强度   
 678: mul r6.xyz, r1.zzzz, r6.xyzx                                          // envSpecluar * envCube
 679: add r12.xyz, r14.xyzx, r19.xyzx                                       // gEnvDiffuseAndRim + ambientAndLightResultCol             
 680: mad r6.xyz, r6.xyzx, r10.xyzx, r12.xyzx                              // envSpecluar * envCube * shColor + gEnvDiffuseAndRim + ambientAndLightResultCol         // 方向光 环境光计算结果   mainlightResultColor
 681: ushr r4.xw, r9.xxxy, l(5, 0, 0, 5)                                       // screenPos >> 5
 682: imad r1.z, r4.w, cb2[0].w, r4.x                                           // r4.w * cb2[0].w + r4.x        index
 683: ishl r2.y, r1.z, l(3)                                                     // r1.z << 3  //index * 8
 684: mad r3.w, -cb0[65].y, cb2[2].w, v9.w                                  // 深度计算
 685: ftoi r3.w, r3.w
 686: iadd r4.x, r3.w, -cb2[1].y
 687: iadd r4.x, r4.x, l(1)
 688: imax r4.x, r4.x, l(0)
 689: imin r4.x, r4.x, l(1)
 690: iadd r4.w, cb2[1].y, l(-1)               // cb2[1].y - 1
 691: imin r3.w, r3.w, r4.w
 692: ishl r3.w, r3.w, l(3)                                                         // 转换为inidex
 693: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r10.x, r2.y, l(0), t0.xxxx
 694: bfi r12.xyzw, l(29, 29, 29, 29), l(3, 3, 3, 3), r1.zzzz, l(1, 2, 3, 4)          index++ 
 695: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r10.y, r12.x, l(0), t0.xxxx
 696: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r10.z, r12.y, l(0), t0.xxxx
 697: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r10.w, r12.z, l(0), t0.xxxx
 698: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r12.x, r12.w, l(0), t0.xxxx
 699: bfi r13.xyz, l(29, 29, 29, 0), l(3, 3, 3, 0), r1.zzzz, l(5, 6, 7, 0)
 700: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r12.y, r13.x, l(0), t0.xxxx
 701: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r12.z, r13.y, l(0), t0.xxxx
 702: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r12.w, r13.z, l(0), t0.xxxx
 703: iadd r1.z, r3.w, cb0[90].y
 704: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r2.y, r1.z, l(0), t0.xxxx
 705: iadd r3.w, -r4.x, l(1)
 706: imul null, r13.x, r2.y, r3.w
 707: iadd r14.xyzw, r1.zzzz, l(1, 2, 3, 4)
 708: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r2.y, r14.x, l(0), t0.xxxx
 709: imul null, r13.y, r3.w, r2.y
 710: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r2.y, r14.y, l(0), t0.xxxx
 711: imul null, r13.z, r3.w, r2.y
 712: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r2.y, r14.z, l(0), t0.xxxx
 713: imul null, r13.w, r3.w, r2.y
 714: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r2.y, r14.w, l(0), t0.xxxx
 715: imul null, r14.x, r3.w, r2.y
 716: iadd r15.xyz, r1.zzzz, l(5, 6, 7, 0)
 717: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r1.z, r15.x, l(0), t0.xxxx
 718: imul null, r14.y, r3.w, r1.z
 719: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r1.z, r15.y, l(0), t0.xxxx
 720: imul null, r14.z, r3.w, r1.z
 721: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r1.z, r15.z, l(0), t0.xxxx
 722: imul null, r14.w, r3.w, r1.z
 723: and r10.xyzw, r10.xyzw, r13.xyzw
 724: and r12.xyzw, r12.xyzw, r14.xyzw
 725: mov x0[0].x, r10.x
 726: mov x0[1].x, r10.y
 727: mov x0[2].x, r10.z
 728: mov x0[3].x, r10.w
 729: mov x0[4].x, r12.x
 730: mov x0[5].x, r12.y
 731: mov x0[6].x, r12.z
 732: mov x0[7].x, r12.w            // 八个额外光源的index
 733: ge r1.x, r1.x, l(0.5000)                                      // metallic > 0.5
 734: mad r1.z, r2.w, l(-0.2500), l(0.7500)                       // 0.75 - 0.25 * (1 - curSceneShadow)
 735: mad r0.xyz, r0.xyzx, r2.zzzz, l(-0.5000, -0.5000, -0.5000, 0.0000)    // diffuseColor - 0.5 
 736: and r1.x, r1.x, l(1.0000)                     // metallic > 0.5
 737: add r2.y, -r1.y, l(0.0100)                    // 0.01 - roughnessSqr
 738: mov r10.w, l(1.0000)
 739: mov r12.w, l(1.0000)
 740: mov r13.xyz, r6.xyzx                      // mainlightResultColor
 741: mov r2.z, l(0)                            // addLightIndex
 742: loop
 743:   ult r2.w, l(7), r2.z          // 7 < r2.z   addLightIndex          两级索引
 744:   breakc_nz r2.w
 745:   mov r2.w, x0[r2.z + 0].x
 746:   ishl r3.w, r2.z, l(5)           // r2.z * 32
 747:   mov r14.xyz, r13.xyzx           // mainlightResultColor
 748:   mov r4.x, r2.w
 749:   loop
 750:     breakc_z r4.x         // 没有光源退出   
 751:     firstbit_lo r4.w, r4.x           // 准确的有数据位置         
 752:     iadd r6.w, r3.w, r4.w             // 两级索引计算index                 baseIndex
 753:     ishl r4.w, l(1), r4.w             //  当前数据位置bitmask
 754:     xor r4.w, r4.w, r4.x              // 处理了 位置bit清零
 755:     bfi r15.xyzw, l(29, 29, 29, 29), l(3, 3, 3, 3), r6.wwww, l(1, 5, 6, 7)          // 组合出索引
 756:     ftou r7.w, cb3[r15.y + 6].w     //       所有访问都+6 说明数从序号6开始
 757:     ieq r7.w, r7.w, l(1)             // cb3[r15.y + 6].w == 1
 758:     if_nz r7.w              // 光源是否启用bound
 759:       ushr r16.xyz, cb3[r15.y + 6].xyzx, l(16, 16, 16, 0)    // 高位
 760:       f16tof32 r17.xyz, cb3[r15.y + 6].xyzx         // 低位的值
 761:       f16tof32 r16.xyz, r16.xzyx                      // 高位的值
 762:       ushr r19.xyz, cb3[r15.z + 6].xyzx, l(16, 16, 16, 0)
 763:       f16tof32 r20.xyz, cb3[r15.z + 6].xyzx           // 低位的值
 764:       f16tof32 r19.xyw, r19.xyxz                                  // 高位的值
 765:       add r10.xyz, v1.xyzx, -cb3[r15.x + 6].xyzx              // positionWS - lightPos          // pos
 766:       mov r24.xz, r17.xxyx
 767:       mov r24.yw, r16.xxxz
 768:       dp4 r7.w, r10.xyzw, r24.xyzw
 769:       mov r16.x, r17.z
 770:       mov r16.z, r20.x
 771:       mov r16.w, r19.x
 772:       dp4 r8.w, r10.xyzw, r16.xyzw
 773:       mov r19.xz, r20.yyzy
 774:       dp4 r9.z, r10.xyzw, r19.xyzw            // 估计是将灯光方向转换光源投影空间
 775:       max r7.w, abs(r7.w), abs(r8.w)
 776:       max r7.w, abs(r9.z), r7.w
 777:       lt r8.w, l(1.0000), r7.w      // 1 < r7.w
 778:       if_nz r8.w                 // 超出lighting bound continue
 779:         mov r4.x, r4.w
 780:         continue
 781:       endif
 782:       mad r8.w, cb3[r15.w + 6].x, l(0.5000), l(0.5000)          // cb3[r15.w + 6].x * 0.5 + 0.5
 783:       add r7.w, r7.w, -r8.w            // 
 784:       add r8.w, -r8.w, l(1.0000)           // 
 785:       div_sat r7.w, r7.w, r8.w            // (r7.w - r8.w) / (1 - r8.w)
 786:       add r7.w, -r7.w, l(1.0000)        // 1 - (r7.w - r8.w) / (1 - r8.w)
 787:       mul r7.w, r7.w, r7.w           //  r7.w * r7.w
 788:     else
 789:       mov r7.w, l(1.0000)         // 设置为1                distanceAtten
 790:     endif
 791:     ishl r8.w, r6.w, l(3)         // baseIndex << 3                        
 792:     ftou r9.z, cb3[r8.w + 6].w        // cb3[r8.w + 6]  xyz lightColor 
 793:     ult r10.x, r9.z, l(2)           // cb3[r8.w + 6].w < 2               //  cb3[r8.w + 6].w相当于光源方向类型   （方向光 点光等）
 794:     if_nz r10.x          // 灯光方向类型                    
 795:       bfi r10.x, l(29), l(3), r6.w, l(3)      // 计算光参数偏移
 796:       add r10.y, cb0[169].w, cb3[r10.x + 6].z  //cb0[169].w + cb3[r10.x + 6].z
 797:       lt r10.y, r10.y, l(0.5000)          //cb0[169].w + cb3[r10.x + 6].z < 0.5
 798:       ieq r10.z, l(16), cb3[r10.x + 6].w      // 16 == cb3[r10.x + 6].w                 //cb3[r10.x + 6].w 辅助光类型
 799:       or r10.y, r10.y, r10.z          // 16 == cb3[r10.x + 6].w || cb0[169].w + cb3[r10.x + 6].z < 0.5
 800:       if_z r10.y                  //继续类型 开启判断
 801:         bfi r10.yz, l(0, 29, 29, 0), l(0, 3, 3, 0), r6.wwww, l(0, 2, 4, 0)
 802:         ieq r6.w, l(4), cb3[r10.x + 6].w          // cb3[r10.x + 6].w  == 4   // 光源render方式4         光源的render方式
 803:         and r9.z, r9.z, l(1)                        // cb3[r8.w + 6].w & 1         灯光方向类型cb3[r8.w + 6].w > 0   不是方向聚光灯
 804:         ine r11.z, r9.z, l(0)                         //  相当于cb3[r8.w + 6].w > 0  灯光方向类型
 805:         lt r13.w, l(0), cb3[r10.y + 6].z          // 0 < cb3[r10.y + 6].z                     FCapsuleLight  Capsule.Length 
 806:         and r11.z, r11.z, r13.w                   // cb3[r8.w + 6].w > 0 && 0 < cb3[r10.y + 6].z  // 光照方式？ 是否tube light
 807:         mad r13.w, cb3[r10.y + 6].y, l(0.5000), l(0.5000)          // cb3[r10.y + 6].y * 0.5 + 0.5
 808:         add r16.z, r13.w, -abs(cb3[r10.y + 6].x)             // (cb3[r10.y + 6].y * 0.5 + 0.5) - abs(cb3[r10.y + 6].x)               // Y * 0.5 + 0.5 - abs(X)   a           Y = a + b
 809:         add r16.x, -r16.z, cb3[r10.y + 6].y               //       cb3[r10.y + 6].y -   r16.z                                         // Y * 0.5 - (0.5 - abs(X))  b         abs(X) = 0.5(b−a+1)    其实是一个hemioOctahedron变换， 然后把其中一个缩放偏移到(0, 1)范围然后符号为作为y的方向判断
 810:         add r13.w, -abs(r16.z), l(1.0000)                 //  1 - abs(r16.z)
 811:         add r13.w, -abs(r16.x), r13.w                    // 1 - abs(r16.z) - abs(r16.x)
 812:         max r13.w, r13.w, l(0.0000)                      //     max(1 - abs(r16.z) - abs(r16.x)， 0)                  
 813:         ge r14.w, cb3[r10.y + 6].x, l(0)              // cb3[r10.y + 6].x > 0
 814:         movc r16.y, r14.w, r13.w, -r13.w            // y的符号判断
 815:         dp3 r13.w, r16.xyzx, r16.xyzx
 816:         rsq r13.w, r13.w
 817:         mul r16.xyz, r13.wwww, r16.xyzx               // noramlize(r16.xyz)            LightData.Tangent
 818:         lt r13.w, l(0.5000), cb3[r10.z + 6].z          // 0.5 < cb3[r10.z + 6].z 
 819:         and r13.w, r6.w, r13.w                            // 光源render方式4 && 0.5 < cb3[r10.z + 6].z 
 820:         add r17.xyz, -v1.xyzx, cb3[r15.x + 6].xyzx        // lightPos - positionWS   // addlightDir
 821:         dp3 r14.w, r17.yzxy, -r16.xyzx                // dot(addLightDir, - LightData.Tangent)
 822:         and r13.w, r13.w, l(1.0000)                   // 光源render方式4 && 0.5 < cb3[r10.z + 6].z  
 823:         movc r13.w, r9.z, l(0), r13.w               // 不是方向聚光灯 ? 0 : 光源render方式4 && 0.5 < cb3[r10.z + 6].z  //对于方向光必须 必须是render方式为4 和0.5 < cb3[r10.z + 6].z 才固定方向
 824:         mad r19.xyz, r14.wwww, -r16.zxyz, -r17.xyzx
 825:         mad r17.xyz, r13.wwww, r19.xyzx, r17.xyzx            // lerp(addlightDir, dot(addLightDir, - LightData.Tangent) * - LightData.Tangent, r13.w)  // 使用类似点光的方向 还是 固定的光照方向  auxLightDir 
 826:         dp3 r13.w, r17.xyzx, r17.xyzx
 827:         rsq r14.w, r13.w
 828:         mul r12.xyz, r14.wwww, r17.xyzx             // normalize(r17.xyz)              normAuxLightDir
 829:         add r14.w, cb3[r10.z + 6].y, cb3[r10.z + 6].y    // 
 830:         max r14.w, r14.w, l(0.1000)                  // max(0.1, cb3[r10.z + 6].y * 2)
 831:         movc r14.w, r6.w, r14.w, cb3[r15.z + 6].w     // 光源render方式4 ?  max(0.1, cb3[r10.z + 6].y * 2) : cb3[r15.z + 6].w    
 832:         mul r19.xyz, r16.zxyz, cb3[r10.y + 6].zzzz                                //    LightData.Tangent *  cb3[r10.y + 6].z
 833:         mad r20.xyz, -r19.xyzx, l(0.5000, 0.5000, 0.5000, 0.0000), r17.xyzx       // auxLightDir - 0.5 *  LightData.Tangent *  cb3[r10.y + 6].z   // shiftLightDir1        ToLight - 0.5 * Capsule.Length * LightData.Tangent;
 834:         mad r19.xyz, r19.xyzx, l(0.5000, 0.5000, 0.5000, 0.0000), r17.xyzx     // auxLightDir + 0.5 *  LightData.Tangent *  cb3[r10.y + 6].z      // shiftLightDir2               //FCapsuleLight 胶囊体光源 参考unreal5
 835:         dp3 r15.y, r20.xyzx, r20.xyzx                    // shiftLen1   
 836:         dp3 r15.z, r19.xyzx, r19.xyzx                     // shiftLen2
 837:         sqrt r15.yz, r15.yyzy                             // shiftLengh               
 838:         dp3 r16.w, r20.xyzx, r19.xyzx                         // dot(shiftLightDir1, shiftLightDir2)
 839:         mad r16.w, r15.y, r15.z, r16.w            // shiftLengh.x * shiftLengh.y + dot(shiftLightDir1, shiftLightDir2)       shfitLenFactor
 840:         mad r16.w, r16.w, l(0.5000), l(1.0000)        // shfitLenFactor * 0.5 + 1
 841:         rcp r16.w, r16.w                                      //   
 842:         mul r21.yzw, r12.xxyz, r16.xxyz                   // 
 843:         mad r21.yzw, r16.zzxy, r12.yyzx, -r21.yyzw       // r16.zzxy * r12.yyzx - r12.xxyz * r16.xxyz     // corss( LightData.Tangent, normAuxLightDir)
 844:         dp3 r17.w, r21.yzwy, r21.yzwy
 845:         rsq r17.w, r17.w
 846:         mul r21.yzw, r17.wwww, r21.yyzw            // normalize(corss( LightData.Tangent, normAuxLightDir))       // biAuxDir
 847:         mul r22.yzw, r16.xxyz, r21.yyzw
 848:         mad r21.yzw, r21.wwyz, r16.yyzx, -r22.yyzw        //  r21.wwyz *  r16.yyzx - r16.xxyz * r21.yyzw         // cross(biAuxDir,  LightData.Tangent)
 849:         dp3 r17.w, r21.yzwy, r21.yzwy
 850:         rsq r17.w, r17.w
 851:         mul r24.xyz, r17.wwww, r21.yzwy               // normalize(cross(biAuxDir,  LightData.Tangent))   orthoDir
 852:         dp3 r17.w, r24.xyzx, r20.xyzx            // dot(orthoDir, shiftLightDir1)                                         //Real Shading in Unreal Engine 4 方程 16
 853:         div r15.y, r17.w, r15.y                   // dot(orthoDir, shiftLightDir1) / shiftLengh.x              dot1
 854:         dp3 r17.w, r24.xyzx, r19.xyzx          // dot(orthoDir, shiftLightDir2)
 855:         div r15.z, r17.w, r15.z                   // dot(orthoDir, shiftLightDir2) / shiftLengh.y    相当于单位向量点积  dot2
 856:         add r15.y, r15.z, r15.y                   // dot1 + dot2
 857:         mul_sat r15.y, r15.y, l(0.5000)           // saturate((dot1 + dot2) * 0.5)
 858:         mul r24.w, r15.y, r16.w                   // saturate((dot1 + dot2) * 0.5) / (shfitLenFactor * 0.5 + 1)         lightIrradiance  // Real Shading in Unreal Engine 4 方程 16   
 859:         movc r19.xyzw, r11.zzzz, r24.xyzw, r12.xyzw           // 光照方式？ ?  orthoDir  : normAuxLightDir                // curLightDir
 860:         lt r12.x, r14.w, l(0)                                     // (光源render方式4 ?  max(0.1, cb3[r10.z + 6].y * 2) : cb3[r15.z + 6].w) < 0
 861:         add r12.y, r13.w, l(1.0000)                                   // AuxLightDirLenSqr + 1
 862:         div r12.y, l(1.0000, 1.0000, 1.0000, 1.0000), r12.y         // 1 / ( AuxLightDirLenSqr + 1)
 863:         and r11.z, r11.z, l(1.0000)                           // 光照方式？
 864:         add r12.z, -r12.y, r19.w                                  // 
 865:         mad r11.z, r11.z, r12.z, r12.y                            //    光照方式？ ? r19.w :  1 / ( AuxLightDirLenSqr + 1)    见GetLocalLightAttenuation bInverseSquared   面光源走前面分支   加入了tube light
 866:         mul r12.y, cb3[r15.x + 6].w, cb3[r15.x + 6].w
 867:         mul r12.y, r12.y, r13.w                                        // cb3[r15.x + 6].w * cb3[r15.x + 6].w * AuxLightDirLenSqr            cb3[r15.x + 6].w ==   LightData.InvRadius
 868:         mad r12.y, -r12.y, r12.y, l(1.0000)                   // 1 - r12.y * r12.y    
 869:         max r12.y, r12.y, l(0)
 870:         mul r12.y, r12.y, r12.y                                  // (1 - r12.y * r12.y)^2       
 871:         mul r11.z, r11.z, r12.y                              // r11.z *  r12.y            //  见GetLocalLightAttenuation bInverseSquared   面光源走前面分支 distance相关atten
 872:         mul r17.xyz, r17.xyzx, cb3[r15.x + 6].wwww      // auxLightDir * cb3[r15.x + 6].w
 873:         dp3 r12.y, r17.xyzx, r17.xyzx       
 874:         min r12.y, r12.y, l(1.0000)
 875:         add r12.y, -r12.y, l(1.0000)             // 1 - lenSqr
 876:         log r12.y, r12.y
 877:         mul r12.y, r12.y, r14.w
 878:         exp r12.y, r12.y                // pow(1 - lenSqr, r14.w)
 879:         mul r12.y, r12.y, r19.w               // r19.w  * pow(1 - lenSqr, r14.w)           //见GetLocalLightAttenuation  RadialAttenuationMask
 880:         movc r11.z, r12.x, r11.z, r12.y            // (光源render方式4 ?  max(0.1, cb3[r10.z + 6].y * 2) : cb3[r15.z + 6].w) < 0 ? r11.z : r12.y    // GetLocalLightAttenuation 相当于判断走bInverseSquared
 881:         dp3 r12.x, r19.yzxy, -r16.xyzx                    // dot( -LightData.Tangent, curLightDir)          // dot(L, -SpotDirection) 对于spotlight
 882:         add r12.x, r12.x, -cb3[r10.y + 6].z            // dot( LightData.Tangent, curLightDir) - cb3[r10.y + 6].z
 883:         mul_sat r12.x, r12.x, cb3[r10.y + 6].w         // saturate(cb3[r10.y + 6].w * (dot( LightData.Tangent, curLightDir) - cb3[r10.y + 6].z))    //SpotAttenuationMask unreal  SpotAngles
 884:         mul r12.x, r12.x, r12.x                   // r12.x * r12.x        // SpotAttenuation 
 885:         mul r12.x, r11.z, r12.x                   //  r11.z * r12.x 
 886:         movc r11.z, r9.z, r11.z, r12.x        // 不是方向聚光灯 ? r11.z : r12.x           ?? SpotAttenuation
 887:         mul r7.w, r7.w, r11.z            //  distanceAtten * SpotAttenuation           LightMask
 888:         lt r11.z, l(0), r7.w            //  
 889:         if_nz r11.z                   // 在衰减范围之内 if( LightMask > 0 )
 890:           if_nz r6.w       // 辅助光render类型4 强度混合类型
 891:             dp3 r11.z, r5.xyzx, r19.xyzx                     // dot(normalWS, representLightDir)          // ndotRL
 892:             add_sat r11.z, r11.z, l(0.5000)                     // saturate(ndotRL + 0.5)
 893:             mad r12.x, r11.z, l(-2.0000), l(3.0000)
 894:             mul r11.z, r11.z, r11.z
 895:             mul r11.z, r11.z, r12.x                  // smoothstep(0, 1, saturate(ndotRL + 0.5))         lightRadian
 896:             add r12.x, l(1.0000), -cb3[r10.z + 6].w              // 1 - cb3[r10.z + 6].w
 897:             mad r11.z, r11.z, cb3[r10.z + 6].w, r12.x          // lerp(1, lightRadian, cb3[r10.z + 6].w)
 898:             mul r11.z, r11.z, cb3[r10.z + 6].x                // cb3[r10.z + 6].x *  lerp(1, lightRadian, cb3[r10.z + 6].w) _lightRadian
 899:             mul r11.z, r7.w, r11.z                                // LightMask * _lightRadian
 900:             add r12.xyz, -r14.xyzx, cb3[r8.w + 6].xyzx          // addLightColor
 901:             mad r14.xyz, r11.zzzz, r12.xyzx, r14.xyzx          // lerp(mainlightResultColor, addLightColor,  LightMask * _lightRadian)  = mainlightResultColor
 902:             mov r12.xyz, r14.xyzx                  // mainlightResultColor
 903:           else
 904:             mov r12.xyz, r14.xyzx              // mainlightResultColor
 905:           endif
 906:           if_z r6.w   // 辅助光render类型不为4
 907:             ieq r15.yz, l(0, 1, 3, 0), cb3[r10.x + 6].wwww            // cb3[r10.x + 6].wwww == (0, 1, 3, 0)   光源的render方式
 908:             if_z cb3[r10.x + 6].w    //光源的render方式为0
 909:               mul r16.xyz, r7.wwww, cb3[r8.w + 6].xyzx                 // LightMask * addLightColor   
 910:               max r11.z, r16.y, r16.x                         // 
 911:               max r11.z, r16.z, r11.z                     //  max(LightMask * addLightColor.rgb)       LColorMax
 912:               mul r11.z, r1.z, r11.z                      // (0.75 - 0.25 * (1 - curSceneShadow)) * LColorMax    补充光源阴影出大一点
 913:               max r11.z, r11.z, l(1.0000)                 // max(r11.z, 1)             LColorMaxS
 914:               rcp r11.z, r11.z                            // 1 / LColorMaxS
 915:               add r13.w, l(1.0000), -cb3[r10.z + 6].y      // 
 916:               mad r11.z, r11.z, cb3[r10.z + 6].y, r13.w       // lerp(1, 1 / LColorMaxS, cb3[r10.z + 6].y)  LColorMaxNorm
 917:               mul r16.xyz, r11.zzzz, cb3[r8.w + 6].xyzx       // addLightColor * LColorMaxNorm
 918:               mul r11.z, l(0.2500), cb3[r10.z + 6].x              // cb3[r10.z + 6].x * 0.25
 919:               dp3 r13.w, r8.xyzx, r19.xyzx                        // dot(normalTWS, representLightDir)     ndotRLTWS
 920:               add_sat r13.w, r13.w, l(0.5000)                      // saturate(ndotRLTWS + 0.5)
 921:               mad r14.w, -cb3[r10.z + 6].x, l(0.2500), l(1.0000)        //
 922:               mad r11.z, r13.w, r14.w, r11.z                          // lerp(cb3[r10.z + 6].x * 0.25, 1, ndotRLTWS)
 923:               mul r16.xyz, r11.zzzz, r16.xyzx                 // addLightColor * LColorMaxNorm * lerp(cb3[r10.z + 6].x * 0.25, 1, ndotRLTWS)   == addLightColor
 924:               mov r17.xyz, r18.xyzx                           // resultDiffuse                  Diif
 925:               mov r20.xyz, r18.xyzx                           // resultDiffuse                      shadowDiif
 926:               mov r11.z, l(1.0000)
 927:             else
 928:               ftoi r13.w, cb3[r10.x + 6].x                    // cb3[r10.x + 6].x
 929:               add r21.yzw, v1.xxyz, -cb3[r15.x + 6].xxyz      // positionWS - lightPos    // lightToPos
 930:               lt r22.yzw, abs(r21.zzww), abs(r21.yyyz)        // (z < y, w < y, w < z)
 931:               and r14.w, r22.z, r22.y                 // z < y && w < y
 932:               lt r24.xyz, l(0, 0, 0, 0), r21.yzwy         // 0 < lightToPos
 933:               ushr r15.x, cb3[r10.y + 6].w, l(24)         // cb3[r10.y + 6].w 的最高八位
 934:               ubfe r22.yz, l(0, 8, 8, 0), l(0, 16, 8, 0), cb3[r10.y + 6].wwww                    //cb3[r10.y + 6].w  中间的两个八位  cb3[r10.y + 6].wwww 在不是方向聚光灯的时候会改变含义
 935:               movc r15.x, r24.x, r15.x, r22.y                         //r24.x  选择高位 低位
 936:               and r10.y, l(255), cb3[r10.y + 6].w                 // cb3[r10.y + 6].w 的最低八位
 937:               movc r10.y, r24.y, r22.z, r10.y                 // r24.y 选择高位 低位
 938:               ubfe r16.w, l(8), l(8), cb3[r10.x + 6].x        // cb3[r10.x + 6].x   次低八位
 939:               and r17.w, l(255), cb3[r10.x + 6].x             //cb3[r10.x + 6].x   最低八位
 940:               movc r16.w, r24.z, r16.w, r17.w            // r24.z 选择高位 低位
 941:               movc r10.y, r22.w, r10.y, r16.w          // w < z 选择  (r24.y 选择高位 低位) : (r24.z 选择高位 低位)
 942:               movc r10.y, r14.w, r15.x, r10.y             // z < y && w < y  选择 (r24.x  选择高位 低位) : r10.y                     // 相当于选着lightToPos 绝对值最大的分量的影响
 943:               ilt r14.w, r10.y, l(80)                     // r10.y < 80   
 944:               movc r10.y, r14.w, r10.y, l(-1)             // r10.y < 80 ? r10.y : -1           要小于80才起效
 945:               movc r9.z, r9.z, r10.y, r13.w         // 不是方向聚光灯 ? r10.y : cb3[r10.x + 6].x                    // LDataIndex
 946:               ige r10.y, r9.z, l(0)               // r9.z >= 0          是否有阴影  // 从lightToPos的方位选择      
 947:               if_nz r10.y
 948:                 dp3 r10.y, r21.yzwy, r21.yzwy                 // 
 949:                 max r10.y, r10.y, l(0.0000)
 950:                 rsq r10.y, r10.y
 951:                 mul r21.yzw, r10.yyyy, r21.yyzw               // normalize(lightToPos)
 952:                 dp3 r10.y, r5.xyzx, r21.yzwy                  // dot(normalWS, lightToPos)       ndotLP
 953:                 max r10.y, r10.y, l(0)                        // max(ndotLP, 0)
 954:                 min r10.y, r10.y, l(0.9000)                   // min(ndotLP, 0.9)
 955:                 add r10.y, -r10.y, l(1.0000)                  // 1 - ndotLP               //相当于背光边缘
 956:                 mul r22.yz, r10.yyyy, cb4[r9.z + 256].xxyx        // (1 - ndotLP) *  cb4[r9.z + 256].xy
 957:                 mul r10.y, r22.z, l(5.0000)                   // r22.z * 5
 958:                 mad r21.yzw, -r21.yyzw, r22.yyyy, v1.xxyz     // positionWS - lightToPos * r22.y
 959:                 mad r21.yzw, r5.xxyz, r10.yyyy, r21.yyzw      //positionWS - lightToPos * r22.y +  normalWS * r22.z * 5          // offsetPosWS                  相当于ApplyShadowBias
 960:                 ishl r10.y, r9.z, l(2)                            // r9.z << 2
 961:                 mul r24.xyzw, r21.zzzz, cb4[r10.y + 33].xyzw          //
 962:                 mad r24.xyzw, cb4[r10.y + 32].xyzw, r21.yyyy, r24.xyzw  // 
 963:                 mad r24.xyzw, cb4[r10.y + 34].xyzw, r21.wwww, r24.xyzw
 964:                 add r24.xyzw, r24.xyzw, cb4[r10.y + 35].xyzw             // offsetPosWS         == > lightCoord
 965:                 div r21.yzw, r24.xxyz, r24.wwww                          // lightCoord
 966:                 add r22.yz, -cb4[r9.z + 312].xxyx, cb4[r9.z + 312].zzwz    //
 967:                 mad r22.yz, r21.yyzy, r22.yyzy, cb4[r9.z + 312].xxyx         // lerp(cb4[r9.z + 312].xy, cb4[r9.z + 312].zw, lightCoord.xy)       // 相当于变换到当前shadow图集的uv范围
 968:                 ge r24.xyz, l(0, 0, 0, 0), r21.yzwy
 969:                 ge r25.xyz, r21.yzwy, l(1.0000, 1.0000, 1.0000, 0.0000)          // 判断范围之外
 970:                 or r24.xyz, r24.xyzx, r25.xyzx
 971:                 or r10.y, r24.y, r24.x
 972:                 or r10.y, r24.z, r10.y                                    // lightCoord 在范围之外
 973:                 and r13.w, r21.w, l(0x7fffffff)                       // 
 974:                 ult r13.w, l(0x7f800000), r13.w                   // infinity
 975:                 or r10.y, r10.y, r13.w                            // lightCoord 在范围之外
 976:                 mad r21.yz, r22.yyzy, cb4[368].zzwz, l(0.0000, 0.5000, 0.5000, 0.0000)                  //unity urp SampleShadow_ComputeSamples_Tent_5x5
 977:                 round_ni r21.yz, r21.yyzy
 978:                 mad r22.yz, r22.yyzy, cb4[368].zzwz, -r21.yyzy
 979:                 add r24.xyzw, r22.yyzz, l(0.5000, 1.0000, 0.5000, 1.0000)
 980:                 mul r25.xyzw, r24.xxzz, r24.xxzz
 981:                 mul r24.xz, r25.yywy, l(0.0800, 0.0000, 0.0800, 0.0000)
 982:                 mad r25.xy, r25.xzxx, l(0.5000, 0.5000, 0.0000, 0.0000), -r22.yzyy
 983:                 add r25.zw, -r22.yyyz, l(0.0000, 0.0000, 1.0000, 1.0000)
 984:                 min r26.xy, r22.yzyy, l(0, 0, 0, 0)
 985:                 mad r26.xy, -r26.xyxx, r26.xyxx, r25.zwzz
 986:                 max r22.yz, r22.yyzy, l(0, 0, 0, 0)
 987:                 mad r22.yz, -r22.yyzy, r22.yyzy, r24.yywy
 988:                 add r26.xy, r26.xyxx, l(1.0000, 1.0000, 0.0000, 0.0000)
 989:                 add r22.yz, r22.yyzy, l(0.0000, 1.0000, 1.0000, 0.0000)
 990:                 mul r27.xy, r25.xyxx, l(0.1600, 0.1600, 0.0000, 0.0000)
 991:                 mul r25.xy, r25.zwzz, l(0.1600, 0.1600, 0.0000, 0.0000)
 992:                 mul r26.xy, r26.xyxx, l(0.1600, 0.1600, 0.0000, 0.0000)
 993:                 mul r28.xy, r22.yzyy, l(0.1600, 0.1600, 0.0000, 0.0000)
 994:                 mul r22.yz, r24.yywy, l(0.0000, 0.1600, 0.1600, 0.0000)
 995:                 mov r27.z, r26.x
 996:                 mov r27.w, r22.y
 997:                 mov r25.z, r28.x
 998:                 mov r25.w, r24.x
 999:                 add r29.xyzw, r25.zwxz, r27.zwxz
 000:                 mov r26.z, r27.y
 001:                 mov r26.w, r22.z
 002:                 mov r28.z, r25.y
 003:                 mov r28.w, r24.z
 004:                 add r22.yzw, r26.zzyw, r28.zzyw
 005:                 div r24.xyz, r25.xzwx, r29.zwyz
 006:                 add r24.xyz, r24.xyzx, l(-2.5000, -0.5000, 1.5000, 0.0000)
 007:                 div r25.xyz, r28.zywz, r22.yzwy
 008:                 add r25.xyz, r25.xyzx, l(-2.5000, -0.5000, 1.5000, 0.0000)
 009:                 mul r24.xyz, r24.yxzy, cb4[368].xxxx
 010:                 mul r25.xyz, r25.xyzx, cb4[368].yyyy                          // shadowAtlas_TexelSize
 011:                 mov r24.w, r25.x
 012:                 mad r26.xyzw, r21.yzyz, cb4[368].xyxy, r24.ywxw
 013:                 mad r27.xy, r21.yzyy, cb4[368].xyxx, r24.zwzz
 014:                 mov r25.w, r24.y
 015:                 mov r24.yw, r25.yyyz
 016:                 mad r28.xyzw, r21.yzyz, cb4[368].xyxy, r24.xyzy
 017:                 mad r25.xyzw, r21.yzyz, cb4[368].xyxy, r25.wywz
 018:                 mad r24.xyzw, r21.yzyz, cb4[368].xyxy, r24.xwzw
 019:                 mul r30.xyzw, r22.yyyz, r29.zwyz
 020:                 mul r31.xyzw, r22.zzww, r29.xyzw
 021:                 mul r13.w, r22.w, r29.y             // 
 022:                 sample_c_lz(texture2d)(float,float,float,float) r14.w, r26.xyxx, t1.xxxx, s2, r21.w                //  r21.w lightcoord.z          SampleShadow_ComputeSamples_Tent_5x5
 023:                 sample_c_lz(texture2d)(float,float,float,float) r15.x, r26.zwzz, t1.xxxx, s2, r21.w
 024:                 mul r15.x, r15.x, r30.y
 025:                 mad r14.w, r30.x, r14.w, r15.x
 026:                 sample_c_lz(texture2d)(float,float,float,float) r15.x, r27.xyxx, t1.xxxx, s2, r21.w
 027:                 mad r14.w, r30.z, r15.x, r14.w
 028:                 sample_c_lz(texture2d)(float,float,float,float) r15.x, r25.xyxx, t1.xxxx, s2, r21.w
 029:                 mad r14.w, r30.w, r15.x, r14.w
 030:                 sample_c_lz(texture2d)(float,float,float,float) r15.x, r28.xyxx, t1.xxxx, s2, r21.w
 031:                 mad r14.w, r31.x, r15.x, r14.w
 032:                 sample_c_lz(texture2d)(float,float,float,float) r15.x, r28.zwzz, t1.xxxx, s2, r21.w
 033:                 mad r14.w, r31.y, r15.x, r14.w
 034:                 sample_c_lz(texture2d)(float,float,float,float) r15.x, r25.zwzz, t1.xxxx, s2, r21.w
 035:                 mad r14.w, r31.z, r15.x, r14.w
 036:                 sample_c_lz(texture2d)(float,float,float,float) r15.x, r24.xyxx, t1.xxxx, s2, r21.w
 037:                 mad r14.w, r31.w, r15.x, r14.w
 038:                 sample_c_lz(texture2d)(float,float,float,float) r15.x, r24.zwzz, t1.xxxx, s2, r21.w
 039:                 mad r13.w, r13.w, r15.x, r14.w                    // shadow 表示厚度
 040:                 add r13.w, r13.w, l(-1.0000) 
 041:                 mad r9.z, cb4[r9.z + 256].w, r13.w, l(1.0000)           // lerp(1, r13.w, cb4[r9.z + 256].w)
 042:                 movc r11.z, r10.y, l(1.0000), r9.z      // 范围之外 ？ 1 : r9.z          // backRimFactor   shadowFactor
 043:               else
 044:                 dp2 r9.z, r4.yzyy, r19.xzxx            // dot(objectDir, representLightDir)    xz平面
 045:                 add_sat r11.z, r9.z, l(1.0000)        // saturate(dot(objectDir, representLightDir) + 1)               shadowFactor
 046:               endif
 047:               mov r16.xyz, cb3[r8.w + 6].xyzx         // lightColRadiance
 048:               mov r17.xyz, l(0, 0, 0, 0)              // Diif
 049:               mov r20.xyz, l(0, 0, 0, 0)              // shadowDiif
 050:             endif
 051:             dp3 r8.w, r8.xyzx, r19.xyzx           // dot(normalTWS, representLightDir)     ndotRLTWS
 052:             if_nz r15.y           //光源render方式为1
 053:               add r9.z, r8.w, cb3[r10.z + 6].x                  //  cb3[r10.z + 6].x + ndotRLTWS
 054:               max_sat r9.z, r9.z, l(-1.0000)                   // saturate(max(-1, cb3[r10.z + 6].x + ndotRLTWS))  nRadia
 055:               mul r8.w, r11.z, r9.z                               // shadowFactor * saturate(max(-1, cb3[r10.z + 6].x + ndotRLTWS))
 056:               mul r20.xyz, r3.xyzx, cb3[r10.z + 6].yyyy            //shadowDiffuseColor * cb3[r10.z + 6].y                   // shadowDiif
 057:               mov r17.xyz, r11.xywx                               //  diffuseColor                 Diif
 058:             else
 059:               mov_sat r8.w, r8.w                 // saturate(ndotRLTWS)        nRadia
 060:             endif
 061:             if_nz r15.z                       // 光源render方式为3
 062:               mul r21.yzw, r19.zzxy, cb0[6].xxyz                      // camVector * representLightDir
 063:               mad r21.yzw, cb0[6].zzxy, r19.xxyz, -r21.yyzw       // cross(representLightDir, camVector)   crossLDir
 064:               mul r22.yzw, r21.yyzw, cb0[6].zzxy
 065:               mad r21.yzw, cb0[6].yyzx, r21.zzwy, -r22.yyzw       // cross(camVector, orthoLDir)      orthoLDir
 066:               dp3 r9.z, r21.yzwy, r21.yzwy
 067:               rsq r9.z, r9.z
 068:               mul r21.yzw, r9.zzzz, r21.yyzw                  // normalize(orthoLDir)
 069:               dp3_sat r8.w, r8.xyzx, -r21.yzwy                // saturate(dot(normalTWS, -orthoLDir))         背光？  nRadia
 070:               mad r15.xy, cb3[r10.z + 6].xxxx, l(-0.6000, -0.4000, 0.0000, 0.0000), l(0.8000, 0.9000, 0.0000, 0.0000)    // (0.8, 0.9) - cb3[r10.z + 6].x * (0.6, 0.4)     bIntens
 071:               add r9.z, -r15.x, r15.y                             // bIntens.y - bIntens.x
 072:               add r10.y, -r15.x, r22.x                            // reverseNdotV.x - bIntens.x
 073:               div r9.z, l(1.0000, 1.0000, 1.0000, 1.0000), r9.z
 074:               mul_sat r9.z, r9.z, r10.y                              // saturate((reverseNdotV.x - bIntens.x) / (bIntens.y - bIntens.x))    rNdotVFactor
 075:               mad r10.y, r9.z, l(-2.0000), l(3.0000)
 076:               mul r9.z, r9.z, r9.z
 077:               mul r9.z, r9.z, r10.y                               // smoothstep(rNdotVFactor)
 078:               mul r9.z, r11.z, r9.z                                   // shadowFactor * smoothstep(rNdotVFactor)
 079:               mul r7.w, r7.w, r9.z                            // LightMask * shadowFactor * smoothstep(rNdotVFactor)      // LightMask
 080:               mad r17.xyz, cb3[r10.z + 6].yyyy, r0.xyzx, l(0.5000, 0.5000, 0.5000, 0.0000)    // (diffuseColor - 0.5) * cb3[r10.z + 6].y + 0.5      Diif
 081:               mov r20.xyz, l(0, 0, 0, 0)            // shadowDiif
 082:             endif
 083:             if_z r15.z         // 光源render方式不为3
 084:               ieq r9.z, l(2), cb3[r10.x + 6].w              // 光源render方式2
 085:               add r10.x, l(0.0500), cb3[r10.z + 6].x       // cb3[r10.z + 6].x + 0.05
 086:               add r10.x, r2.x, -r10.x                       // roughness - (cb3[r10.z + 6].x + 0.05)
 087:               mul_sat r10.x, r10.x, l(-10.0000)            // saturate((roughness - (cb3[r10.z + 6].x + 0.05)) * -10)          rRough           roughness小于cb3[r10.z + 6].x + 0.05的区域
 088:               mad r10.y, r10.x, l(-2.0000), l(3.0000)
 089:               mul r10.x, r10.x, r10.x
 090:               mul r10.x, r10.x, r10.y                             // smoothstep(rRough)
 091:               add r10.y, l(1.0000), -cb3[r10.z + 6].z             // 1 - b3[r10.z + 6].z
 092:               mad r10.y, r1.x, cb3[r10.z + 6].z, r10.y    // lerp(1,  metallic > 0.5, cb3[r10.z + 6].z)      是否只影响金属 
 093:               mul r10.x, r10.y, r10.x                   // lerp(1,  metallic > 0.5, cb3[r10.z + 6].z) * smoothstep(rRough)     // isGlossOrMetal
 094:               mov r10.y, cb3[r10.z + 6].y                         // cb3[r10.z + 6].y 
 095:               movc r10.xy, r9.zzzz, r10.xyxx, l(1.0000, 0.0000, 0.0000, 0.0000)         // 光源render方式2 ？(isGlossOrMetal, cb3[r10.z + 6].y) : (1, 0)
 096:               mad r9.z, r10.y, r2.y, r1.y                        //  lerp(roughnessSqr, 0.01, r10.y)    mRoughnessSqr          cb3[r10.z + 6].y
 097:               mad r15.xyz, v4.xyzx, r5.wwww, r19.xyzx      // viewDirWS + representLightDir          halfRepDir
 098:               dp3 r10.y, r15.xyzx, r15.xyzx
 099:               max r10.y, r10.y, l(0.0000)
 100:               rsq r10.y, r10.y
 101:               mul r15.xyz, r10.yyyy, r15.xyzx                 // normalize(halfRepDir)
 102:               dp3 r10.y, r7.xyzx, r15.xyzx                    // dot(normalTWS, halfRepDir)    noh
 103:               mul r10.z, r9.z, r9.z                                                                       // D_GGX(float Roughness, float NoH)
 104:               mad r11.z, r10.y, r10.z, -r10.y                 // noh * mRoughnessSqr * mRoughnessSqr - noh
 105:               mad r10.y, r11.z, r10.y, l(1.0000)           // noh * (noh * noh * mRoughnessSqr * mRoughnessSqr - noh) + 1                 D
 106:               mul r10.y, r10.y, r10.y      
 107:               ne r11.z, r10.y, r10.z
 108:               div r10.y, r10.z, r10.y           //     r10.z / r10.y
 109:               movc r10.y, r11.z, r10.y, l(1.0000)   // D                      // D_GGX(float Roughness, float NoH) end
 110:               mad r9.z, r21.x, l(2.0000), r9.z    //  
 111:               add r9.z, r9.z, l(0.0001)                               // ggxTerm
 112:               rcp r9.z, r9.z
 113:               mul r9.z, r9.z, r10.y              // D / (ndotv * 2 + mRoughnessSqr) ggxTerm
 114:               mad r9.z, r9.z, l(0.5000), l(-0.0001)
 115:               max r9.z, r9.z, l(0)
 116:               min r9.z, r9.z, l(100.0000)         // min(100, max(ggxTerm * 0.5 - 0.0001, 0))
 117:               mul r15.xyz, r23.xyzx, r9.zzzz                      // styleSpecularColor * ggxTerm
 118:               mul r10.xyz, r10.xxxx, r15.xyzx             // isGlossOrMetal * styleSpecularColor * ggxTerm   specualrTerm
 119:               mul r10.xyz, r10.xyzx, cb3[r15.w + 6].zzzz       // b3[r15.w + 6].z * specualrTerm
 120:             else
 121:               mov r10.xyz, l(0, 0, 0, 0)         // specularTerm
 122:             endif
 123:             add r15.xyz, r17.xyzx, -r20.xyzx
 124:             mad r15.xyz, r8.wwww, r15.xyzx, r20.xyzx                   // lerp(shadowDiif, Diif, nRadia)
 125:             mul r16.xyz, r16.xyzx, r7.wwww             // addLightColor * LightMask
 126:             mul r15.xyz, r15.xyzx, r16.xyzx           // addLightColor * LightMask * lerp(shadowDiif, Diif, nRadia)
 127:             mul r10.xyz, r10.xyzx, r16.xyzx        // specularTerm * addLightColor * LightMask 
 128:             mul r10.xyz, r8.wwww, r10.xyzx        // nRadia * specularTerm * addLightColor * LightMask 
 129:             mad r10.xyz, r15.xyzx, r1.wwww, r10.xyzx   // lerp(1, baseColor.w, cb5[9].w) * diffu + specu       addLightResult
 130:             add r14.xyz, r10.xyzx, r14.xyzx          // mainlightResultColor + addLightResult
 131:           endif
 132:         else       // // 在衰减范围之内 if( LightMask > 0 ) 之外
 133:           mov r12.xyz, r14.xyzx            //mainlightResultColor
 134:           mov r6.w, l(0)
 135:         endif
 136:         movc r14.xyz, r6.wwww, r12.xyzx, r14.xyzx            // mainlightResultColor + r6.wwww * r12.xyzx
 137:       endif
 138:     endif
 139:     mov r4.x, r4.w
 140:   endloop
 141:   mov r13.xyz, r14.xyzx                       // finalColor
 142:   iadd r2.z, r2.z, l(1)
 143: endloop
 144: div r0.xyz, r13.xyzx, cb0[89].xxxx              // finalColor / cb0[89].x
 145: eq r1.x, cb5[7].x, l(1.0000)                  //  cb5[7].x == 1   透明判断
 146: movc o0.w, r1.x, r0.w, l(1.0000)             //  输出透明 baseColor.w or 1
 147: lt r0.w, cb0[171].w, l(0.5000)            //是否是延迟渲染的basepass 还是角色的前向渲染
 148: if_nz r0.w    //是否是延迟渲染的basepass 还是角色的前向渲染
{
 149:   eq r0.w, cb0[66].w, l(0)             //cb0[66].w == 0        cb0[66].w  unity_OrthoParams.w          
 150:   add r1.xyz, -v1.xyzx, cb0[32].xyzx              // worldCameraPos - positionWS
 151:   mov r2.x, cb0[0].z
 152:   mov r2.y, cb0[1].z
 153:   mov r2.z, cb0[2].z         //从相机矩阵获取相机朝向   cameraDir
 154:   movc r1.xyz, r0.wwww, r1.xyzx, r2.xyzx            //  viewDirWS                                                                 //Height fog: Analuytic model 见Advances in Lighting And AA Decima Siggraph2017        嗯就是指数高度雾unreal的或者 https://iquilezles.org/articles/fog/
 155:   dp3 r0.w, r1.xyzx, r1.xyzx                            // dot(viewDirWS, viewDirWS)
 156:   sqrt r1.w, r0.w                                      // viewDirLen
 157:   mad r1.w, r1.w, cb0[136].w, -cb0[134].w            // viewDirLen *  cb0[136].w - cb0[134].w
 158:   max r1.w, r1.w, l(0)                                // max(0, viewDirLen *  cb0[136].w - cb0[134].w)  viewDirLen * density - start             // 
 159:   add r2.w, -cb0[133].w, cb0[135].w                   // cb0[135].w - cb0[133].w                           endHeight - startHeight
 160:   mad r3.x, v1.y, l(0.0010), -cb0[133].w            // positionWS.y * 0.001 - cb0[133].w             // curHeightDiffer
 161:   rsq r0.w, r0.w
 162:   mul r1.xyz, r0.wwww, r1.xyzx                        // normalize(viewDirWS)
 163:   dp3 r0.w, -r1.xyzx, cb0[136].xyzx                   // dot(-viewDirWS, cb0[136].xyz)
 164:   add r3.yzw, cb0[132].xxyz, cb0[134].xxyz            // cb0[132].xyz + cb0[134].xyz
 165:   add r4.xyz, r3.yzwy, cb0[133].xyzx                  //  cb0[133].xyz + cb0[132].xyz + cb0[134].xyz                // 
 166:   add r2.w, r2.w, -r3.x                        // cb0[135].w - cb0[133].w - (positionWS.y * 0.001 - cb0[133].w)             heightDelta 
 167:   div r2.w, r2.w, cb0[131].w                  // ( cb0[135].w - cb0[133].w - (positionWS.y * 0.001 - cb0[133].w)) / cb0[131].w          heightDelta / falloff    
 168:   max r2.w, r2.w, l(0.0100)                       // max(r2.w, 0.01)
 169:   mul r4.w, r2.w, l(-1.4427)                  // -1.4427 *  r2.w
 170:   exp r4.w, r4.w                              // exp(-1.4427 *  r2.w)
 171:   add r4.w, -r4.w, l(1.0000)                  // 1 - exp(-1.4427 *  r2.w)
 172:   div r2.w, r4.w, r2.w                      // (1 - exp(-1.4427 *  r2.w)) / r2.w      
 173:   div r3.x, -r3.x, cb0[131].w                       
 174:   mul r3.x, r3.x, l(1.4427)
 175:   exp r3.x, r3.x                      //exp(-curHeightDiffer/cb0[131].w)         
 176:   mul r2.w, r2.w, r3.x               // heightAtten * distAtten
 177:   mul r1.w, -r1.w, r2.w
 178:   mul r5.xyz, r4.xyzx, r1.wwww          // r4.xyz * r1.w
 179:   mul r5.xyz, r5.xyzx, l(1.4427, 1.4427, 1.4427, 0.0000)
 180:   exp r5.xyz, r5.xyzx                            // exp(r4.xyz * r1.w)
 181:   mad r1.w, r0.w, r0.w, l(1.0000)                                     //Rayleigh 散射公式
 182:   mul r1.w, r1.w, l(0.0597)                                       //Rayleigh 散射公式
 183:   mad r2.w, cb0[132].w, cb0[132].w, l(1.0000)               // mie散射公式开始
 184:   add r3.x, cb0[132].w, cb0[132].w
 185:   mad r0.w, -r3.x, r0.w, r2.w
 186:   mad r2.w, -cb0[132].w, cb0[132].w, l(1.0000)
 187:   mul r3.x, r0.w, l(12.5664)
 188:   sqrt r0.w, r0.w
 189:   mul r0.w, r0.w, r3.x
 190:   div r0.w, r2.w, r0.w                                    // mie散射公式结束
 191:   mul r6.xyz, r0.wwww, cb0[132].xyzx                              // mieScattering
 192:   mad r6.xyz, cb0[134].xyzx, r1.wwww, r6.xyzx                     //  rayleigh + mieScattering
 193:   mul r3.xyz, r3.yzwy, cb0[135].xyzx                              //
 194:   mad r3.xyz, cb0[131].xyzx, r6.xyzx, r3.xyzx                             // cb0[131].xyz * (rayleigh + mieScattering) 
 195:   div r3.xyz, r3.xyzx, r4.xyzx                        //                  
 196:   max r3.xyz, r3.xyzx, l(0, 0, 0, 0)
 197:   min r3.xyz, r3.xyzx, l(255.0000, 255.0000, 255.0000, 0.0000)
 198:   add r4.xyz, -r5.xyzx, l(1.0000, 1.0000, 1.0000, 0.0000)
 199:   mul r3.xyz, r3.xyzx, r4.xyzx
 200:   mad r3.xyz, r0.xyzx, r5.xyzx, r3.xyzx                            // //Height fog: Analuytic model 见Advances in Lighting And AA Decima Siggraph2017
 201:   lt r0.w, l(0), cb0[141].z    // 0 < cb0[141].z 
 202:   if_nz r0.w                                      // 0 < cb0[141].z              // 开始了lut
 203:     mad r0.w, v9.w, cb0[142].x, cb0[142].y                 // v9.w   positionCS.w
 204:     log r0.w, r0.w
 205:     mul r0.w, r0.w, cb0[142].z
 206:     div r4.z, r0.w, cb0[141].z                                        // 归一化到纹理坐标Z轴 (可能用于3D纹理采样)
 207:     and r9.w, cb0[88].w, l(7)                                                                     //    cb0[88].w * 7                               
 208:     imad r5.xyz, r9.xywx, l(0x0019660d, 0x0019660d, 0x0019660d, 0), l(0.0146, 0.0146, 0.0146, 0.0000)             // screepos * 0x0019660d + 0.0146
 209:     imad r0.w, r5.y, r5.z, r5.x
 210:     imad r1.w, r5.z, r0.w, r5.y
 211:     imad r2.w, r0.w, r1.w, r5.z
 212:     imad r5.x, r1.w, r2.w, r0.w
 213:     imad r5.y, r2.w, r5.x, r1.w
 214:     ushr r5.xy, r5.xyxx, l(16, 16, 0, 0)
 215:     utof r5.xy, r5.xyxx
 216:     mad r5.xy, r5.xyxx, l(0.0000, 0.0000, 0.0000, 0.0000), l(-1.0000, -1.0000, 0.0000, 0.0000)
 217:     utof r5.zw, r9.xxxy                                       // screenPos
 218:     mad r5.xy, cb0[145].wwww, r5.xyxx, r5.zwzz                // 混合噪声
 219:     mul r4.xy, r5.xyxx, cb0[143].xyxx
 220:     dp3 r0.w, -r1.xyzx, -r2.xyzx              // dot(viewDirWS, cameraDir)        forwardFactor
 221:     lt r1.x, l(0.0000), r0.w                 
 222:     rcp r0.w, r0.w
 223:     and r0.w, r0.w, r1.x                          //   取大于0的值
 224:     mul r0.w, r0.w, cb0[141].w                // 1 / forwardFactor
 225:     add r1.xyz, v1.xyzx, -cb0[32].xyzx  // worldCameraPos - positionWS                    viewDir
 226:     dp3 r1.x, r1.xyzx, r1.xyzx                 // viewDirlengthSqr
 227:     max r1.z, r1.x, l(0.0000)
 228:     rsq r1.z, r1.z                                    // 1 / viewDirlength
 229:     mul r1.w, r1.z, r1.x                          // viewDirlength
 230:     mul r2.x, r0.w, r1.z                               // 1 / (viewDirlength * forwardFactor)
 231:     mad r2.y, r2.x, r1.y, cb0[32].y           // viewDir.y / (viewDirlength * forwardFactor) +  worldCameraPos.y 
 232:     mad r1.y, -r2.x, r1.y, r1.y                           //  viewDir.y -  viewDir.y / (viewDirlength * forwardFactor)
 233:     mad r0.w, -r0.w, r1.z, l(1.0000)
 234:     mul r0.w, r1.w, r0.w
 235:     add r1.w, r2.y, -cb0[137].x
 236:     mul r1.w, r1.w, cb0[137].z
 237:     max r1.w, r1.w, l(-127.0000)
 238:     exp r1.w, -r1.w
 239:     mul r1.w, r1.w, cb0[137].y
 240:     mul r2.x, r1.y, cb0[137].z
 241:     max r2.x, r2.x, l(-127.0000)
 242:     exp r2.z, -r2.x
 243:     add r2.z, -r2.z, l(1.0000)
 244:     div r2.z, r2.z, r2.x
 245:     mad r2.w, -r2.x, l(0.2402), l(0.6931)
 246:     lt r2.x, l(0.0000), abs(r2.x)
 247:     movc r2.x, r2.x, r2.z, r2.w
 248:     mul r1.w, r1.w, r2.x
 249:     lt r2.x, l(0), cb0[140].y
 250:     add r2.y, r2.y, -cb0[140].z
 251:     mul r2.y, r2.y, cb0[140].x
 252:     max r2.y, r2.y, l(-127.0000)
 253:     exp r2.y, -r2.y
 254:     mul r2.y, r2.y, cb0[140].y
 255:     mul r1.y, r1.y, cb0[140].x
 256:     max r1.y, r1.y, l(-127.0000)
 257:     exp r2.z, -r1.y
 258:     add r2.z, -r2.z, l(1.0000)
 259:     div r2.z, r2.z, r1.y
 260:     mad r2.w, -r1.y, l(0.2402), l(0.6931)
 261:     lt r1.y, l(0.0000), abs(r1.y)
 262:     movc r1.y, r1.y, r2.z, r2.w
 263:     mad r1.y, r2.y, r1.y, r1.w
 264:     movc r1.y, r2.x, r1.y, r1.w
 265:     mul r0.w, r0.w, r1.y
 266:     exp r0.w, -r0.w
 267:     min r0.w, r0.w, l(1.0000)
 268:     max r0.w, r0.w, cb0[139].w
 269:     mad r1.y, -r1.x, r1.z, cb0[138].x
 270:     mad r1.x, r1.x, r1.z, -cb0[138].z
 271:     mul_sat r1.xy, r1.xyxx, cb0[138].wyww
 272:     add r0.w, r0.w, r1.y
 273:     add r0.w, r1.x, r0.w
 274:     min r0.w, r0.w, l(1.0000)
 275:     add r1.x, -r0.w, l(1.0000)
 276:     mul r1.xyz, r1.xxxx, cb0[139].xyzx
 277:     sample_l(texture3d)(float,float,float,float) r2.xyzw, r4.xyzx, t15.xyzw, s1, l(0)
 278:     add r1.w, v9.w, -cb0[144].z
 279:     mul_sat r1.w, r1.w, l(1000000.0000)
 280:     add r2.xyzw, r2.xyzw, l(-0.0000, -0.0000, -0.0000, -1.0000)
 281:     mad r2.xyzw, r1.wwww, r2.xyzw, l(0.0000, 0.0000, 0.0000, 1.0000)
 282:     mad r1.xyz, r1.xyzx, r2.wwww, r2.xyzx
 283:     mul r0.w, r0.w, r2.w
 284:   else
 285:     add r2.xyz, v1.xyzx, -cb0[32].xyzx   // positionWS - worldCameraPos
 286:     dp3 r1.w, r2.xyzx, r2.xyzx
 287:     max r2.x, r1.w, l(0.0000)
 288:     rsq r2.x, r2.x
 289:     mul r2.z, r1.w, r2.x
 290:     add r2.w, cb0[32].y, -cb0[137].x
 291:     mul r2.w, r2.w, cb0[137].z
 292:     max r2.w, r2.w, l(-127.0000)
 293:     exp r2.w, -r2.w
 294:     mul r2.w, r2.w, cb0[137].y
 295:     mul r3.w, r2.y, cb0[137].z
 296:     max r3.w, r3.w, l(-127.0000)
 297:     exp r4.x, -r3.w
 298:     add r4.x, -r4.x, l(1.0000)
 299:     div r4.x, r4.x, r3.w
 300:     mad r4.y, -r3.w, l(0.2402), l(0.6931)
 301:     lt r3.w, l(0.0000), abs(r3.w)
 302:     movc r3.w, r3.w, r4.x, r4.y
 303:     mul r2.w, r2.w, r3.w
 304:     lt r3.w, l(0), cb0[140].y
 305:     add r4.x, cb0[32].y, -cb0[140].z
 306:     mul r4.x, r4.x, cb0[140].x
 307:     max r4.x, r4.x, l(-127.0000)
 308:     exp r4.x, -r4.x
 309:     mul r4.x, r4.x, cb0[140].y
 310:     mul r2.y, r2.y, cb0[140].x
 311:     max r2.y, r2.y, l(-127.0000)
 312:     exp r4.y, -r2.y
 313:     add r4.y, -r4.y, l(1.0000)
 314:     div r4.y, r4.y, r2.y
 315:     mad r4.z, -r2.y, l(0.2402), l(0.6931)
 316:     lt r2.y, l(0.0000), abs(r2.y)
 317:     movc r2.y, r2.y, r4.y, r4.z
 318:     mad r2.y, r4.x, r2.y, r2.w
 319:     movc r2.y, r3.w, r2.y, r2.w
 320:     mul r2.y, r2.z, r2.y
 321:     exp r2.y, -r2.y
 322:     min r2.y, r2.y, l(1.0000)
 323:     max r2.y, r2.y, cb0[139].w
 324:     mad r2.z, -r1.w, r2.x, cb0[138].x
 325:     mul_sat r2.z, r2.z, cb0[138].y
 326:     mad r1.w, r1.w, r2.x, -cb0[138].z
 327:     mul_sat r1.w, r1.w, cb0[138].w
 328:     add r2.x, r2.z, r2.y
 329:     add r1.w, r1.w, r2.x
 330:     min r0.w, r1.w, l(1.0000)
 331:     add r1.w, -r0.w, l(1.0000)
 332:     mul r1.xyz, r1.wwww, cb0[139].xyzx
 333:   endif
 334:   mad o0.xyz, r3.xyzx, r0.wwww, r1.xyzx     // finalColor
}
 335: else
 336:   mov o0.xyz, r0.xyzx    // 延迟直接返回diffuseColor
 337: endif
 338: max r0.x, v5.z, l(0.0000)
 339: div r0.xy, v5.xyxx, r0.xxxx
 340: max r0.z, v6.z, l(0.0000)
 341: div r0.zw, v6.xxxy, r0.zzzz
 342: add r0.xy, -r0.zwzz, r0.xyxx
 343: mul r1.xy, r0.xyxx, l(0.5000, -0.5000, 0.0000, 0.0000)
 344: sqrt r1.xy, abs(r1.xyxx)
 345: mov r0.z, -r0.y
 346: lt r0.yw, l(0, 0, 0, 0), r0.xxxz
 347: lt r0.xz, r0.xxzx, l(0, 0, 0, 0)
 348: iadd r0.xy, -r0.ywyy, r0.xzxx
 349: itof r0.xy, r0.xyxx
 350: mul r0.xy, r0.xyxx, r1.xyxx
 351: mad o1.xy, r0.xyxx, l(0.5000, 0.5000, 0.0000, 0.0000), l(0.5000, 0.5000, 0.0000, 0.0000)
 352: mov o1.zw, l(0.0000, 0.0000, 1.0000, 0.4000)
 353: ret
 
 








