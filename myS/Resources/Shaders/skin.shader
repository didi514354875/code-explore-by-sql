明日方舟 终末地  皮肤
Shader hash 275d3f82-7a0adecd-7659c1ff-802353cc

vs_5_0                 和衣服一致
      dcl_globalFlags refactoringAllowed
      dcl_constantbuffer cb0[67], immediateIndexed
      dcl_constantbuffer cb1[27], dynamicIndexed
      dcl_constantbuffer cb2[52], immediateIndexed
      dcl_resource_structured t0, 16
      dcl_input v0.xyz                          // positionOS
      dcl_input v1.xy                           // uv
      dcl_input v2.xyz                          // normalOS   如果法线压缩（Octahedron normal endoding ）并编码到 v2.x 两个10bit中 最后一个10bit存储存储切线位置也是类似于八面体编码只不过只需要考虑2d平面上就可以，因为切线是法线的垂直向量（切线在2d中表示为(a,b), 编码到a+b=1的直线上，只需要存储a）
      dcl_input v3.xyzw                         // TangentOS  
      dcl_input v4.xyz                              //oldPositionOS
      dcl_input_sgv v5.x, instanceid               // SV_INSTANCEID
      dcl_input v6.xyzw                            // blendWeights
      dcl_input v7.xyzw                            // blendIndices
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
   0: and r0.x, v2.x, l(2.0000)
   1: ult r0.x, l(0), r0.x
   2: ibfe r0.yzw, l(0, 10, 10, 10), l(0, 0, 10, 20), v2.xxxx
   3: ushr r1.x, v2.x, l(31)
   4: itof r0.yzw, r0.yyzw
   5: mul r1.yzw, r0.yyzw, l(0.0000, 0.0020, 0.0020, 0.0020)
   6: add r2.xyz, -abs(r1.yzyy), l(1.0000, 1.0000, 1.0000, 0.0000)
   7: add r3.z, -abs(r1.z), r2.x
   8: lt r2.x, r3.z, l(0)
   9: ge r0.yz, r0.yyzy, l(0, 0, 0, 0)
  10: and r0.yz, r0.yyzy, l(0.0000, 1.0000, 1.0000, 0.0000)
  11: mad r0.yz, r0.yyzy, l(0.0000, 2.0000, 2.0000, 0.0000), l(0.0000, -1.0000, -1.0000, 0.0000)
  12: mul r0.yz, r0.yyzy, r2.yyzy
  13: movc r3.xy, r2.xxxx, r0.yzyy, r1.yzyy
  14: dp3 r0.y, r3.xyzx, r3.xyzx
  15: rsq r0.y, r0.y
  16: mul r2.xyz, r0.yyyy, r3.xyzx
  17: mad r3.xyz, r3.yzxy, r0.yyyy, -r2.zxyz
  18: dp3 r0.y, r3.xyzx, r2.xyzx
  19: add r3.xyz, -r0.yyyy, r3.xyzx
  20: dp3 r0.y, r3.xyzx, r3.xyzx
  21: rsq r0.y, r0.y
  22: mul r3.xyz, r0.yyyy, r3.xyzx
  23: mul r4.xyz, r2.zxyz, r3.yzxy
  24: mad r4.xyz, r2.yzxy, r3.zxyz, -r4.xyzx
  25: dp3 r0.y, r4.xyzx, r4.xyzx
  26: rsq r0.y, r0.y
  27: mul r4.xyz, r0.yyyy, r4.xyzx
  28: lt r0.y, r0.w, l(0)
  29: movc r0.y, r0.y, l(-1.0000), l(1.0000)
  30: dp2 r0.z, r1.wwww, r0.yyyy
  31: add r5.x, -r0.z, l(1.0000)
  32: add r0.z, -abs(r5.x), l(1.0000)
  33: mul r5.y, r0.z, r0.y
  34: dp2 r0.y, r5.xyxx, r5.xyxx
  35: rsq r0.y, r0.y
  36: mul r0.yz, r0.yyyy, r5.xxyx
  37: mul r1.yzw, r4.xxyz, r0.zzzz
  38: mad r3.xyz, r0.yyyy, r3.xyzx, r1.yzwy
  39: itof r0.y, r1.x
  40: mad r3.w, r0.y, l(2.0000), l(-1.0000)
  41: movc r0.yzw, r0.xxxx, r2.xxyz, v2.xxyz
  42: movc r1.xyzw, r0.xxxx, r3.xyzw, v3.xyzw
  43: ishl r0.x, v5.x, l(4)
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
 116:   dp4 r3.z, r5.xyzw, r2.xyzw
 117:   dp4 r7.x, r7.xyzw, r2.xyzw
 118:   dp4 r7.y, r9.xyzw, r2.xyzw
 119:   dp4 r7.z, r8.xyzw, r2.xyzw
 120:   dp3 r2.x, r4.xyzx, r0.yzwy
 121:   dp3 r2.y, r6.xyzx, r0.yzwy
 122:   dp3 r2.z, r5.xyzx, r0.yzwy
 123:   dp3 r2.w, r4.xyzx, r1.xyzx
 124:   dp3 r3.w, r6.xyzx, r1.xyzx
 125:   dp3 r1.z, r5.xyzx, r1.xyzx
 126:   mov r1.x, r2.w
 127:   mov r1.y, r3.w
 128: else
 129:   mov r7.xyz, v4.xyzx
 130:   mov r3.xyz, v0.xyzx
 131:   mov r2.xyz, r0.yzwy
 132: endif
 133: mul r4.xyz, r3.yyyy, cb1[r0.x + 1].xyzx
 134: mad r4.xyz, cb1[r0.x + 0].xyzx, r3.xxxx, r4.xyzx
 135: mad r4.xyz, cb1[r0.x + 2].xyzx, r3.zzzz, r4.xyzx
 136: add r4.xyz, r4.xyzx, cb1[r0.x + 3].xyzx
 137: mul r5.xyzw, r4.yyyy, cb0[17].xyzw
 138: mad r5.xyzw, cb0[16].xyzw, r4.xxxx, r5.xyzw
 139: mad r5.xyzw, cb0[18].xyzw, r4.zzzz, r5.xyzw
 140: add o9.xyzw, r5.xyzw, cb0[19].xyzw
 141: add r5.xyz, -r4.xyzx, cb0[32].xyzx
 142: add r6.x, -r5.x, cb0[0].z
 143: add r6.y, -r5.y, cb0[1].z
 144: add r6.z, -r5.z, cb0[2].z
 145: mad r5.xyz, cb0[66].wwww, r6.xyzx, r5.xyzx
 146: dp3 r2.w, r5.xyzx, r5.xyzx
 147: rsq r2.w, r2.w
 148: mul o4.xyz, r2.wwww, r5.xyzx
 149: mad o0.xy, v1.xyxx, cb2[51].xyxx, cb2[51].zwzz
 150: mul r5.xyz, r2.yyyy, cb1[r0.x + 1].xyzx
 151: mad r2.xyw, cb1[r0.x + 0].xyxz, r2.xxxx, r5.xyxz
 152: mad r2.xyz, cb1[r0.x + 2].xyzx, r2.zzzz, r2.xywx
 153: dp3 r2.w, r2.xyzx, r2.xyzx
 154: max r2.w, r2.w, l(0.0000)
 155: rsq r2.w, r2.w
 156: mul o2.xyz, r2.wwww, r2.xyzx
 157: mul r2.xyz, r1.yyyy, cb1[r0.x + 1].xyzx
 158: mad r2.xyz, cb1[r0.x + 0].xyzx, r1.xxxx, r2.xyzx
 159: mad r1.xyz, cb1[r0.x + 2].xyzx, r1.zzzz, r2.xyzx
 160: dp3 r2.x, r1.xyzx, r1.xyzx
 161: max r2.x, r2.x, l(0.0000)
 162: rsq r2.x, r2.x
 163: mul o3.xyz, r1.xyzx, r2.xxxx
 164: mul r1.xyz, r4.yyyy, cb0[25].xywx
 165: mad r1.xyz, cb0[24].xywx, r4.xxxx, r1.xyzx
 166: mad r1.xyz, cb0[26].xywx, r4.zzzz, r1.xyzx
 167: add o5.xyz, r1.xyzx, cb0[27].xywx
 168: lt r1.x, cb1[r0.x + 10].x, l(1.0000)
 169: movc r1.xyz, r1.xxxx, r3.xyzx, r7.xyzx
 170: mul r2.xyzw, r1.yyyy, cb1[r0.x + 7].xyzw
 171: mad r2.xyzw, cb1[r0.x + 6].xyzw, r1.xxxx, r2.xyzw
 172: mad r2.xyzw, cb1[r0.x + 8].xyzw, r1.zzzz, r2.xyzw
 173: add r2.xyzw, r2.xyzw, cb1[r0.x + 9].xyzw
 174: mul r1.xyz, r2.yyyy, cb0[38].xywx
 175: mad r1.xyz, cb0[37].xywx, r2.xxxx, r1.xyzx
 176: mad r1.xyz, cb0[39].xywx, r2.zzzz, r1.xyzx
 177: mad o6.xyz, cb0[40].xywx, r2.wwww, r1.xyzx
 178: mov o3.w, r1.w
 179: mov o1.xyz, r4.xyzx
 180: mov o7.xyz, r0.yzwy
 181: mov o8.xyz, v0.xyzx
 182: mov o10.x, v5.x
 183: ret



Shader hash f22b62dc-a23b5767-c9a75fbb-6900b2a2

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
      dcl_resource_structured t0, 4
      dcl_resource_texture2d (float,float,float,float) t1   // DepthStencilTexture 附加光源的阴影图集
      dcl_resource_texture2d (float,float,float,float) t2   // shadow相关 r通道是场景阴影 g通道是角色自阴影
      dcl_resource_texture3d (float,float,float,float) t3   // volumetric lightmap 相关
      dcl_resource_texture3d (float,float,float,float) t4   // volumetric lightmap 相关
      dcl_resource_texture3d (float,float,float,float) t5   // volumetric lightmap 相关
      dcl_resource_texture2d (float,float,float,float) t6   // ramp图 (diffuse)
      dcl_resource_texture2d (float,float,float,float) t7   // colorgrading lut
      dcl_resource_texture2d (float,float,float,float) t8   // 基础色 baseColor
      dcl_resource_texture2d (float,float,float,float) t9   // 法线贴图 normalMap
      dcl_resource_texture2d (float,float,float,float) t10  // matcap 作为 volumetric lightmap的替代
      dcl_resource_texture3d (float,float,float,float) t11  // volumetric fog
      dcl_input_ps linear v0.xy                             // uv
      dcl_input_ps linear v1.xyz                           // positionWS
      dcl_input_ps linear v2.xyz                          // normalWS
      dcl_input_ps linear v3.xyzw                           // tangentWS
      dcl_input_ps linear v4.xyz                            // viewDirWS
      dcl_input_ps linear v5.xyz                            // nonJitterScreenPos
      dcl_input_ps linear v6.xyz                          // normalOS
      dcl_input_ps_siv linear noperspective v9.xyw, position // positionCS screepos
      dcl_input_ps nointerpolation v10.x                        // instanceID              
      dcl_input_ps_sgv nointerpolation v11.x, isfrontface     //SV_ISFRONTFACE
      dcl_output o0.xyzw
      dcl_output o1.xyzw
      dcl_temps 30
      dcl_indexableTemp x0[8], 4
   0: sample_b(texture2d)(float,float,float,float) r0.xyzw, v0.xyxx, t8.xyzw, s5, cb0[88].x  //SAMPLE_TEXTURECUBE_LOD        baseTex
   1: mul r0.xyz, r0.xyzx, cb5[26].xyzx                                // baseColor
   2: mul r1.xyz, r0.zxyz, l(12.9200, 12.9200, 12.9200, 0.0000)            // real LinearToSRGB(real c) jian urp Color.hlsl
   3: log r2.xyz, abs(r0.zxyz)
   4: mul r2.xyz, r2.xyzx, l(0.4167, 0.4167, 0.4167, 0.0000)
   5: exp r2.xyz, r2.xyzx
   6: mad r2.xyz, r2.xyzx, l(1.0550, 1.0550, 1.0550, 0.0000), l(-0.0550, -0.0550, -0.0550, 0.0000)
   7: ge r3.xyz, l(0.0031, 0.0031, 0.0031, 0.0000), r0.zxyz
   8: movc_sat r1.xyz, r3.xyzx, r1.xyzx, r2.xyzx                    // real LinearToSRGB(real c) end      gradBaseColor
   9: mul r2.xw, r1.xxxz, l(31.0000, 0.0000, 0.0000, 0.9688)            // 类似colorgrading的lut
  10: round_ni r1.w, r2.x         // x round
  11: mad r2.yz, r1.yyzy, l(0.0000, 0.0303, 0.9688, 0.0000), l(0.0000, 0.0005, 0.0156, 0.0000)
  12: mad r2.x, r1.w, l(0.0313), r2.y
  13: sample_l(texture2d)(float,float,float,float) r3.xyz, r2.xzxx, t7.xyzw, s4, l(0)
  14: add r1.yz, r2.xxwx, l(0.0000, 0.0313, 0.0156, 0.0000)
  15: sample_l(texture2d)(float,float,float,float) r2.xyz, r1.yzyy, t7.xyzw, s4, l(0)
  16: mad r1.x, r1.x, l(31.0000), -r1.w
  17: add r1.yzw, -r3.xxyz, r2.xxyz
  18: mad r1.xyz, r1.xxxx, r1.yzwy, r3.xyzx                    // 类似colorgrading的lut 结果urp的 ApplyLut2D 按照32的维度计算  gradBaseColor
  19: sample_b(texture2d)(float,float,float,float) r2.xyz, v0.xyxx, t9.xywz, s6, cb0[88].x  // normalTex
  20: mul r2.x, r2.x, r2.z
  21: mad r2.xy, r2.xyxx, l(2.0000, 2.0000, 0.0000, 0.0000), l(-1.0000, -1.0000, 0.0000, 0.0000)// normalTex
  22: dp2 r1.w, r2.xyxx, r2.xyxx
  23: min r1.w, r1.w, l(1.0000)
  24: add r1.w, -r1.w, l(1.0000)
  25: sqrt r1.w, r1.w
  26: max r1.w, r1.w, l(0.0000)
  27: mul r2.xy, r2.xyxx, cb5[0].wwww    // 应用法线强度
  28: ishl r2.z, v10.x, l(4)
  29: add r3.xy, v1.xzxx, -cb1[r2.z + 3].xzxx   //计算世界坐标xz分量与实例位置偏移的差值（v1.xyz为世界坐标）  objectDir
  30: dp3 r2.w, v2.xyzx, v2.xyzx
  31: rsq r3.z, r2.w
  32: mul r4.xyz, r3.zzzz, v2.xyzx       // normalize(normalWS)
  33: dp2 r3.z, r3.xyxx, r3.xyxx        // 计算xz平面偏移向量的倒数长度
  34: max r3.z, r3.z, l(0.0000)
  35: rsq r3.z, r3.z
  36: mul r3.xy, r3.zzzz, r3.xyxx        // normalize(r4.yz)      objectDir
  37: dp3 r3.z, v4.xyzx, v4.xyzx                    // 
  38: max r3.z, r3.z, l(0.0000)
  39: rsq r3.z, r3.z
  40: mul r5.xyz, r3.zzzz, v4.xyzx      // normalize(viewDirWS)
  41: sqrt r2.w, r2.w
  42: max r2.w, r2.w, l(0.0000)
  43: div r2.w, l(1.0000, 1.0000, 1.0000, 1.0000), r2.w
  44: lt r3.w, l(0), v3.w
  45: movc r3.w, r3.w, l(1.0000), l(-1.0000)
  46: ge r4.w, cb1[r2.z + 5].w, l(0)
  47: movc r4.w, r4.w, l(1.0000), l(-1.0000)
  48: mul r3.w, r3.w, r4.w
  49: mul r6.xyz, v2.zxyz, v3.yzxy
  50: mad r6.xyz, v2.yzxy, v3.zxyz, -r6.xyzx
  51: mul r6.xyz, r3.wwww, r6.xyzx 
  52: mul r7.xyz, r2.wwww, v3.xyzx           // tangent
  53: mul r6.xyz, r2.wwww, r6.xyzx         // // bitangent 
  54: mul r8.xyz, r2.wwww, v2.xyzx         // normal
  55: mul r6.xyz, r2.yyyy, r6.xyzx          // 应用法线贴图的副切线分量强度（来自r2.y）
  56: mad r2.xyw, r2.xxxx, r7.xyxz, r6.xyxz
  57: mad r2.xyw, r1.wwww, r8.xyxz, r2.xyxw         // 切线空间转为世界空间法线
  58: dp3 r1.w, r2.xywx, r2.xywx
  59: rsq r1.w, r1.w
  60: mul r2.xyw, r1.wwww, r2.xyxw                       // normalize(normalTWS)
  61: mad r1.w, cb5[14].w, l(2.0000), l(-1.0000)
  62: movc r1.w, v11.x, l(1.0000), r1.w
  63: mul r2.xyw, r1.wwww, r2.xyxw               // 反转法线 normalTWS
  64: mul r4.xyz, r1.wwww, r4.xyzx            // 反转法线 normalWS        //会在辅助光源中被用到
  65: ftou r6.xy, v9.xyxx
  66: add r1.w, -cb0[91].x, l(1.0000)
  67: mad r1.w, cb0[171].w, r1.w, cb0[91].x
  68: mul r1.w, r1.w, cb0[89].x
  69: dp2 r3.w, r2.xwxx, r2.xwxx
  70: max r3.w, r3.w, l(0.0000)
  71: rsq r3.w, r3.w
  72: mul r7.xy, r2.xwxx, r3.wwww
  73: lt r3.w, cb0[161].y, l(0.5000)            // // ambeintIntenisty
  74: if_nz r3.w                                     // 烘焙光照
{
  75:   add r8.xyz, v1.xyzx, -cb0[175].xyzx
  76:   max r3.w, abs(r8.y), abs(r8.x)
  77:   max r3.w, abs(r8.z), r3.w
  78:   add r4.w, r3.w, l(-896.0000)
  79:   mul_sat r4.w, r4.w, l(0.0156)
  80:   lt r5.w, l(0), cb0[175].w
  81:   lt r7.w, r4.w, l(1.0000)
  82:   and r5.w, r5.w, r7.w
  83:   if_nz r5.w
  84:     add r8.xy, r3.wwww, l(-100.0000, -200.0000, 0.0000, 0.0000)
  85:     mul_sat r8.xy, r8.xyxx, l(0.0833, 0.0625, 0.0000, 0.0000)
  86:     lt r8.xy, r8.xyxx, l(1.0000, 1.0000, 0.0000, 0.0000)
  87:     movc r8.yz, r8.yyyy, l(0.0000, 0.0020, 1.0000, 0.0000), l(0.0000, 0.0005, 2.0000, 0.0000)
  88:     movc r8.xy, r8.xxxx, l(0.0039, 0.0000, 0.0000, 0.0000), r8.yzyy
  89:     mul r8.xzw, r8.xxxx, v1.xxyz
  90:     frc r8.xzw, r8.xxzw
  91:     sample_l(texture3d)(float,float,float,float) r8.xyzw, r8.xzwx, t3.xyzw, s0, r8.y
  92:     mad r8.xyzw, r8.xyzw, l(255.0000, 255.0000, 255.0000, 255.0000), l(0.5000, 0.5000, 0.5000, 0.5000)
  93:     round_ni r8.xyzw, r8.xyzw
  94:     lt r3.w, l(0), r8.w
  95:     if_nz r3.w
  96:       div r9.xyz, v1.xyzx, r8.wwww
  97:       frc r9.xyz, r9.xyzx
  98:       mad r9.xyz, r9.xyzx, l(4.0000, 4.0000, 4.0000, 0.0000), l(0.5000, 0.5000, 0.5000, 0.0000)
  99:       mad r8.xyz, r8.xyzx, l(5.0000, 5.0000, 5.0000, 0.0000), r9.xyzx
 100:       mul r8.xyz, r8.xyzx, cb0[176].xyzx
 101:       sample_l(texture3d)(float,float,float,float) r9.xyz, r8.xyzx, t4.xyzw, s1, l(0)
 102:       mul r8.w, r8.z, l(0.3333)
 103:       sample_l(texture3d)(float,float,float,float) r10.xyz, r8.xywx, t5.xyzw, s1, l(0)
 104:       mad r11.xyz, r8.xyzx, l(1.0000, 1.0000, 0.3333, 0.0000), l(0.0000, 0.0000, 0.3333, 0.0000)
 105:       sample_l(texture3d)(float,float,float,float) r11.xyz, r11.xyzx, t5.xyzw, s1, l(0)
 106:       mad r8.xyz, r8.xyzx, l(1.0000, 1.0000, 0.3333, 0.0000), l(0.0000, 0.0000, 0.6667, 0.0000)
 107:       sample_l(texture3d)(float,float,float,float) r8.xyz, r8.xyzx, t5.xyzw, s1, l(0)
 108:       mad r10.xyz, r10.xyzx, l(4.0000, 4.0000, 4.0000, 0.0000), l(-2.0000, -2.0000, -2.0000, 0.0000)
 109:       mul r10.xyz, r9.xxxx, r10.xyzx
 110:       mad r11.xyz, r11.xyzx, l(4.0000, 4.0000, 4.0000, 0.0000), l(-2.0000, -2.0000, -2.0000, 0.0000)
 111:       mul r11.xyz, r9.yyyy, r11.xyzx
 112:       mad r8.xyz, r8.xyzx, l(4.0000, 4.0000, 4.0000, 0.0000), l(-2.0000, -2.0000, -2.0000, 0.0000)
 113:       mul r8.xyz, r8.xyzx, r9.zzzz
 114:       mov r10.w, r9.x
 115:       add r12.xyzw, -r10.xyzw, cb0[178].xyzw
 116:       mad r10.xyzw, r4.wwww, r12.xyzw, r10.xyzw
 117:       mov r11.w, r9.y
 118:       add r12.xyzw, -r11.xyzw, cb0[179].xyzw
 119:       mad r11.xyzw, r4.wwww, r12.xyzw, r11.xyzw
 120:       mov r8.w, r9.z
 121:       add r9.xyzw, -r8.xyzw, cb0[180].xyzw
 122:       mad r8.xyzw, r4.wwww, r9.xyzw, r8.xyzw
 123:     else
 124:       mov r10.xyzw, cb0[178].xyzw
 125:       mov r11.xyzw, cb0[179].xyzw
 126:       mov r8.xyzw, cb0[180].xyzw
 127:     endif
 128:   else
 129:     mov r10.xyzw, cb0[178].xyzw
 130:     mov r11.xyzw, cb0[179].xyzw
 131:     mov r8.xyzw, cb0[180].xyzw
 132:   endif
 133:   mov r7.z, l(1.0000)
 134:   dp3 r9.x, r10.xzwx, r7.xyzx           // normalTWS  
 135:   dp3 r9.y, r11.xzwx, r7.xyzx
 136:   dp3 r9.z, r8.xzwx, r7.xyzx
 137:   max r9.xyz, r9.xyzx, l(0, 0, 0, 0)          //SHEvalLinearL0L1   // shColor
 138:   mul r12.xyz, r1.wwww, r9.xyzx           // shColor * r2.w    originSHColor
 139:   mul r13.xyz, r11.xyzx, l(0.7152, 0.7152, 0.7152, 0.0000)
 140:   mad r13.xyz, r10.xyzx, l(0.2126, 0.2126, 0.2126, 0.0000), r13.xyzx
 141:   mad r13.xyz, r8.xyzx, l(0.0722, 0.0722, 0.0722, 0.0000), r13.xyzx
 142:   dp3 r3.w, r13.xyzx, r13.xyzx
 143:   max r3.w, r3.w, l(0.0000)
 144:   rsq r3.w, r3.w
 145:   mul r13.xyz, r3.wwww, r13.xyzx
 146:   mov r13.y, abs(r13.y)
 147:   mov r13.w, l(1.0000)
 148:   dp4 r10.x, r10.xyzw, r13.xyzw
 149:   dp4 r10.y, r11.xyzw, r13.xyzw
 150:   dp4 r10.z, r8.xyzw, r13.xyzw
 151:   max r8.xyz, r10.xyzx, l(0, 0, 0, 0)
 152:   max r3.w, r8.y, r8.x
 153:   max r3.w, r8.z, r3.w
 154:   mul r3.w, r1.w, r3.w
 155:   ge r4.w, r12.y, r12.z
 156:   and r4.w, r4.w, l(1.0000)
 157:   mov r8.xy, r12.zyzz
 158:   mov r8.zw, l(0.0000, 0.0000, -1.0000, 0.6667)
 159:   mad r9.xy, r9.yzyy, r1.wwww, -r8.xyxx
 160:   mov r9.zw, l(0.0000, 0.0000, 1.0000, -1.0000)
 161:   mad r8.xyzw, r4.wwww, r9.xyzw, r8.xyzw
 162:   ge r4.w, r12.x, r8.x
 163:   and r4.w, r4.w, l(1.0000)
 164:   mov r9.xyz, r8.xywx
 165:   mov r9.w, r12.x
 166:   mov r8.xyw, r9.wywx
 167:   add r8.xyzw, -r9.xyzw, r8.xyzw
 168:   mad r8.xyzw, r4.wwww, r8.xyzw, r9.xyzw
 169:   min r4.w, r8.y, r8.w
 170:   add r4.w, -r4.w, r8.x
 171:   add r5.w, -r8.y, r8.w
 172:   mad r7.z, r4.w, l(6.0000), l(0.0001)
 173:   div r5.w, r5.w, r7.z
 174:   add r5.w, r5.w, r8.z
 175:   add r7.z, r8.x, l(0.0001)
 176:   div r4.w, r4.w, r7.z
 177:   frc r5.w, abs(r5.w)
 178:   add r9.xyzw, r5.wwww, l(-0.5000, 1.0000, 0.6667, 0.3333)
 179:   add r5.w, abs(r9.x), l(-0.4500)
 180:   mul_sat r5.w, r5.w, l(-10.0000)
 181:   mad r7.z, r5.w, l(-2.0000), l(3.0000)
 182:   mul r5.w, r5.w, r5.w
 183:   mul r5.w, r5.w, r7.z
 184:   mad r5.w, r5.w, l(-0.3500), l(0.7000)
 185:   mov_sat r8.x, r8.x
 186:   mul r5.w, r5.w, r8.x
 187:   min r4.w, r4.w, r5.w
 188:   add r5.w, -r4.w, l(2.0000)
 189:   rcp r5.w, r5.w
 190:   add r5.w, r5.w, r5.w
 191:   frc r8.xyz, r9.yzwy
 192:   mad r8.xyz, r8.xyzx, l(6.0000, 6.0000, 6.0000, 0.0000), l(-3.0000, -3.0000, -3.0000, 0.0000)
 193:   add_sat r8.xyz, abs(r8.xyzx), l(-1.0000, -1.0000, -1.0000, 0.0000)
 194:   add r8.xyz, r8.xyzx, l(-1.0000, -1.0000, -1.0000, 0.0000)
 195:   mad r8.xyz, r4.wwww, r8.xyzx, l(1.0000, 1.0000, 1.0000, 0.0000)
 196:   mul r8.xyz, r5.wwww, r8.xyzx         // HSVTORGB end                      shColor
 197:   mov r4.w, l(1.0000)
 198:   mov r1.w, r3.w      //SHDominantIntensity            ambeintIntenisty
 199: else
 200:   lt r3.w, l(1.5000), cb0[161].y
 201:   if_nz r3.w
 202:     mul r9.xyz, r2.yyyy, cb0[1].xyzx
 203:     mad r9.xyz, cb0[0].xyzx, r2.xxxx, r9.xyzx
 204:     mad r9.xyz, cb0[2].xyzx, r2.wwww, r9.xyzx
 205:     dp3 r3.w, r9.xyzx, r9.xyzx
 206:     rsq r3.w, r3.w
 207:     mul r7.zw, r3.wwww, r9.xxxy
 208:     mad r7.zw, r7.zzzw, l(0.0000, 0.0000, 0.5000, 0.5000), l(0.0000, 0.0000, 0.5000, 0.5000)
 209:     sample_b(texture2d)(float,float,float,float) r9.xyw, r7.zwzz, t10.yzwx, s7, cb0[88].x
 210:     ge r3.w, r9.x, r9.y
 211:     and r3.w, r3.w, l(1.0000)
 212:     mov r10.xy, r9.yxyy
 213:     mov r10.zw, l(0.0000, 0.0000, -1.0000, 0.6667)
 214:     add r11.xy, r9.xyxx, -r10.xyxx
 215:     mov r11.zw, l(0.0000, 0.0000, 1.0000, -1.0000)
 216:     mad r10.xyzw, r3.wwww, r11.xyzw, r10.xyzw
 217:     ge r3.w, r9.w, r10.x
 218:     and r3.w, r3.w, l(1.0000)
 219:     mov r9.xyz, r10.xywx
 220:     mov r10.xyw, r9.wywx
 221:     add r10.xyzw, -r9.xyzw, r10.xyzw
 222:     mad r9.xyzw, r3.wwww, r10.xyzw, r9.xyzw
 223:     min r3.w, r9.y, r9.w
 224:     add r3.w, -r3.w, r9.x
 225:     add r5.w, -r9.y, r9.w
 226:     mad r7.z, r3.w, l(6.0000), l(0.0001)
 227:     div r5.w, r5.w, r7.z
 228:     add r5.w, r5.w, r9.z
 229:     add r7.z, r9.x, l(0.0001)
 230:     div r3.w, r3.w, r7.z
 231:     add r7.z, -r3.w, l(2.0000)
 232:     div r7.z, l(2.0000), r7.z
 233:     add r9.xyz, abs(r5.wwww), l(1.0000, 0.6667, 0.3333, 0.0000)
 234:     frc r9.xyz, r9.xyzx
 235:     mad r9.xyz, r9.xyzx, l(6.0000, 6.0000, 6.0000, 0.0000), l(-3.0000, -3.0000, -3.0000, 0.0000)
 236:     add_sat r9.xyz, abs(r9.xyzx), l(-1.0000, -1.0000, -1.0000, 0.0000)
 237:     add r9.xyz, r9.xyzx, l(-1.0000, -1.0000, -1.0000, 0.0000)
 238:     mad r9.xyz, r3.wwww, r9.xyzx, l(1.0000, 1.0000, 1.0000, 0.0000)
 239:     mul r9.xyz, r7.zzzz, r9.xyzx
 240:     add r3.w, -cb0[162].w, l(1.0000)
 241:     mad r8.xyz, r9.xyzx, cb0[162].wwww, r3.wwww
 242:   else
 243:     mov r8.xyz, cb0[163].xyzx            // shColor
 244:   endif
 245:   mov r13.xyz, l(0, 0, 0, 0)               // dominantSHDir
 246:   mov r12.xyz, l(1.0000, 1.0000, 1.0000, 0.0000) // originSHColor
 247:   mov r4.w, l(0)                        // r4.w设置为0   dominantOn
 248: endif
}
 249: dp2 r3.w, r7.xyxx, cb0[166].xzxx        // ndotsky      normalTWS   xz
 250: add_sat r3.w, r3.w, cb0[167].x
 251: mad r3.w, r3.w, cb0[167].y, cb0[167].z // saturate(ndotsky +  cb0[167].x) * cb0[167].y + cb0[167].z    应用光照强度与偏移：intensity*scale + bias     ndotSky
 252: dp3 r5.w, r2.xywx, r5.xyzx          // dot(normalTWS, viewDirWS)
 253: mov_sat r7.x, r5.w                    // saturate          ndotvTWS
 254: mad r7.y, r7.x, l(0.8500), l(0.1500)   // ndotvTWS * 0.85 + 0.15 
 255: add r7.y, -r7.y, l(1.0000)            // 1 - ndotvTWS
 256: mul_sat r7.y, r7.y, cb5[2].z              // saturate(cb5[2].z * (1 - ndotvTWS))
 257: add r7.z, -r7.y, l(1.0000)                // 
 258: mad r7.yzw, cb5[24].xxyz, r7.yyyy, r7.zzzz    // lerp(1,  cb5[24].xyz, saturate(cb5[2].z * (1 - ndotvTWS)))
 259: mul r9.xyz, r0.xyzx, r7.yzwy                      //      baseColor * lerp(1,  cb5[24].xyz, saturate(cb5[2].z * (1 - ndotvTWS)))   rimTintBaseColor
 260: add r10.xyz, cb5[19].xyzx, cb1[r2.z + 13].xzyx        // 
 261: add r11.xy, -r10.xyxx, cb0[170].ywyy            //
 262: mad r10.xy, cb0[170].xxxx, r11.xyxx, r10.xyxx // lerp(cb5[19].xy + cb1[r4.x + 13].xz, cb0[170].yw, cb0[170].x)    //xyControl
 263: add r2.z, -r10.z, l(1.0000)
 264: mad r2.z, cb0[170].x, r2.z, r10.z   // / lerp(r11.z, 1, cb0[170].x)    // 距离差
 265: add r8.w, r10.y, -v1.y            // r11.y - posiotionWS.y           // 高度差
 266: add r8.w, r8.w, l(0.2000)           // r11.y - posiotionWS.y + 0.2
 267: mul_sat r8.w, r8.w, l(2.8571)      // // saturate(r7.w * 2.8571)
 268: mad r9.w, r8.w, l(-2.0000), l(3.0000)
 269: mul r8.w, r8.w, r8.w
 270: mul r8.w, r8.w, r9.w           // smoothstep(0, 1, r7.w)
 271: mul r9.w, r2.z, r8.w      // r2.z * smoothstep(0, 1, r7.w)  距离差 和高度差的影响
 272: mad r2.z, r8.w, r2.z, r10.x   // //  smoothstep(0, 1, r7.w) * r6.w  + r11.x 
 273: lt r2.z, l(0.0001), r2.z          // / 是否有下雨的水滴效果
 274: max r8.w, r9.w, r10.x                             //  max(xyControl.x, r9.w)   //  dotD
 275: add r10.xy, -cb5[0].xyxx, l(1.0000, 1.0000, 0.0000, 0.0000)            // 1 - cb5[0].xy
 276: mad r9.w, r8.w, r10.y, cb5[0].y               // dotD * r10.y + cb5[0].y    lerp(1, dotD, cb5[0].y)
 277: add r10.y, -r10.x, l(0.5000)          // 0.5 - (1 - cb5[0].x)
 278: mad r8.w, r8.w, r10.y, r10.x        // dotD * (1 - 0.5 - r10.x) + r10.x  dotD * (1 - r10.x) + r10.x - 0.5dotD     lerp(0.5*dotD, 1 - 0.5*dotD, 1 - cb5[0].x)
 279: movc r9.w, r2.z, r9.w, cb5[0].y       // r2.z ? lerp(1, dotD, cb5[0].y) : cb5[0].y      //specualrF
 280: movc r2.z, r2.z, r8.w, r10.x                 //  r2.z ? lerp(0.5*dotD, 1 - 0.5*dotD, 1 - cb5[0].x) :  1 - cb5[0].x         // roughness
 281: mad r8.w, -cb5[0].z, l(0.9600), l(0.9600)  // // 0.96 - cb5[0].z * 0.96          metallic
 282: mul r10.xyz, r8.wwww, r9.xyzx                 // rimTintBaseColor * ( 0.96 - cb5[0].z * 0.96  )   diffuseColor
 283: mul r9.w, r9.w, l(0.0400)                     // r9.w * 0.04        f0
 284: mad r0.xyz, r0.xyzx, r7.yzwy, -r9.wwww        //  
 285: mad r0.xyz, cb5[0].zzzz, r0.xyzx, r9.wwww       //    lerp(r9.w * 0.04, rimTintBaseColor, cb5[0].z)  specularColor
 286: mul r1.xyz, r1.xyzx, r8.wwww            //gradBaseColor * (0.96 - cb5[0].z * 0.96)   shadowDiffuseColor
 287: mul r7.y, r2.z, r2.z                  // roughness * roughness         roughnessSqr
 288: max r7.y, r7.y, l(0.0078)                   // / max(roughnessSqr, 0.0078)
 289: add r11.xyz, cb0[164].xyzx, cb3[0].xyzx    // 
 290: mad r11.xyz, cb0[161].wwww, r11.xyzx, -cb3[0].xyzx  // lerp(-cb3[0].xyz, cb0[164].xyz, cb0[161].w)         // lightDir  
 291: dp2 r7.z, r11.xzxx, r11.xzxx
 292: max r7.z, r7.z, l(0.0000)
 293: rsq r7.z, r7.z
 294: mul r7.zw, r7.zzzz, r11.xxxz                              // normalize(r13.xz)        // lightXZ
 295: add r14.xyz, cb0[171].xyzx, -cb3[3].xyzx
 296: mad r14.xyz, cb0[165].wwww, r14.xyzx, cb3[3].xyzx   // // lerp(cb3[3].xyzx, cb0[165].xyzx, cb0[165].wwww)   // lightCol
 297: add r9.w, -cb3[3].w, l(1.0000)
 298: mad r9.w, cb0[171].w, r9.w, cb3[3].w        // lerp(cb3[3].w, 1, cb0[171].w)
 299: mul r15.xyz, r9.wwww, r14.xyzx                // lerp(cb3[3].xyzx, cb0[165].xyzx, cb0[165].wwww) * lerp(cb3[3].w, 1, cb0[171].w)    // lightColor
 300: dp3 r10.w, r15.xyzx, l(0.2127, 0.7152, 0.0722, 0.0000)  // rIntesity
 301: mov r6.z, l(0)
 302: ld_indexable(texture2d)(float,float,float,float) r15.xy, r6.xyzz, t2.xyzw   // screenPos 采样   ShadowTex
 303: ftoi r6.z, cb4[31].x                              // 
 304: ilt r6.z, l(0), r6.z                //  0 < cb4[31].x
 305: movc r6.z, r6.z, r15.x, cb4[31].z // 0 < cb4[31].x ? ShadowTex.x : cb4[31].z      // 是否获取场景阴影
 306: add r6.z, r6.z, l(-1.0000)
 307: mad r6.z, cb4[30].x, r6.z, l(1.0000)     //  lerp(1, shadowTex.x, cb4[30].x)  应用阴影全局强度   sceneShadow
 308: add r11.w, -r6.z, l(1.0000)
 309: mad r6.z, cb0[161].z, r11.w, r6.z    // lerp(sceneShadow, 1,  cb0[161].z)    场景阴影强度    curSceneShadow
 310: dp3 r11.w, r2.xywx, r11.xyzx          // dot(normalTWS, lightDir)    ndotlt
 311: mul r15.xzw, r1.xxyz, cb0[160].zzzz   // shadowDiffuseColor * cb0[160].z    shadowDiffuseColor             cb0[160].z 暗部强度
 312: mul r16.xyz, r15.xzwx, l(0.6500, 0.6500, 0.6500, 0.0000)    // shadowDiffuseColor * cb0[160].z * 0.65     satDiff
 313: dp3 r12.w, r16.xyzx, l(0.2127, 0.7152, 0.0722, 0.0000)      // 计算灰度值 satDiffIntensity
 314: mad r16.xyz, r15.xzwx, l(0.6500, 0.6500, 0.6500, 0.0000), -r12.wwww
 315: mad r16.xyz, r16.xyzx, l(1.2000, 1.2000, 1.2000, 0.0000), r12.wwww             lerp(satDiffIntensity, satDiff, 1.2)     //_2ndShadowDiffuseColor
 316: dp3 r12.w, r10.xyzx, l(0.2127, 0.7152, 0.0722, 0.0000)                // diffIntensity
 317: mad r17.xyz, r9.xyzx, r8.wwww, -r12.wwww
 318: mad r17.xyz, r17.xyzx, l(1.2000, 1.2000, 1.2000, 0.0000), r12.wwww // lerp(diffInteisty, diffuseColor, 1.2)  增强饱和度  _2ndDiffuseColor
 319: mad r11.w, cb0[164].w, cb0[163].w, r11.w           // ndotlt + cb0[164].w * cb0[163].w       //  cb0[163].w 背光相关
 320: max r11.w, r11.w, l(-1.0000)                      // 
 321: min r11.w, r11.w, l(1.0000)                           //  限制范围
 322: mad r18.x, r11.w, l(0.5000), l(0.5000)      //  r11.w* 0.5 + 0.5
 323: mov r18.y, l(0.5000)
 324: sample_l(texture2d)(float,float,float,float) r18.xyzw, r18.xyxx, t6.xyzw, s3, l(0)    // rampTex
 325: max r11.w, r18.y, r18.x
 326: max r11.w, r18.z, r11.w
 327: min r13.w, r18.y, r18.x
 328: min r13.w, r18.z, r13.w
 329: add r11.w, r11.w, -r13.w                  //  max - min          // rampTexRange
 330: mul r13.w, r0.w, r15.y                        // baseTex.w * ShadowTex.y           baseTex.w        AO
 331: mad_sat r14.w, r0.w, r15.y, r18.w             // saturate(rampTex.w + baseTex.w * ShadowTex.y)   rampRadiance
 332: mad r19.xyz, r1.xyzx, cb0[160].zzzz, -r16.xyzx   
 333: mad r16.xyz, r14.wwww, r19.xyzx, r16.xyzx   // lerp(_2ndShadowDiffuseColor, shadowDiffuseColor, rampRadiance)   //  combineShadowDiffuseColor
 334: min r14.w, r0.w, r15.y                    // min(AO, ShadowTex.y)
 335: min r16.w, r18.w, r14.w                   //  // min(rampTex.w, min(AO, ShadowTex.y))  ==> rampShadowRadiance
 336: min r17.w, cb0[161].y, l(1.0000)
 337: mul r17.w, r16.w, r17.w
 338: add r19.xyz, -r8.xyzx, l(1.0000, 1.0000, 1.0000, 0.0000)
 339: mad r8.xyz, r17.wwww, r19.xyzx, r8.xyzx
 340: mul r8.xyz, r3.wwww, r8.xyzx
 341: mad r19.xyz, r14.xyzx, r9.wwww, -r10.wwww
 342: mad r19.xyz, r16.wwww, r19.xyzx, r10.wwww
 343: max r20.xy, r1.wwww, l(0.0000, 1.2500, 0.0000, 0.0000)
 344: min r20.xy, r20.xyxx, l(1.5000, 1.7500, 0.0000, 0.0000)     ==>  mulIntesity
 345: mul r20.xzw, r8.xxyz, r20.xxxx      // ndotSky * ambientCol * mulIntesity.x
 346: add r3.w, -cb0[165].w, l(1.0000)
 347: mad r21.xyz, r14.xyzx, cb0[165].wwww, r3.wwww   // lerp(lightCol, 1, cb0[165].w)    // cb0[165].w 光照颜色选择
 348: mad r19.xyz, r20.xzwx, r21.xyzx, r19.xyzx
 349: mad r1.w, r1.w, l(0.3500), l(0.6500)
 350: min r1.w, r1.w, l(1.5000)
 351: add r3.w, -r1.w, r20.y
 352: mad r1.w, cb0[161].x, r3.w, r1.w
 353: mul r8.xyz, r8.xyzx, r1.wwww
 354: mul r8.xyz, r8.xyzx, cb0[160].wwww    // ndotSky * ambientCol * mulIntesity1 * cb0[160].w
 355: mad r19.xyz, r19.xyzx, cb0[160].yyyy, -r8.xyzx
 356: mad r8.xyz, r6.zzzz, r19.xyzx, r8.xyzx // lerp(ndotSky * ambientCol * mulIntesity1 * cb0[160].w, lightAndAmbientCol * cb0[160].y, curSceneShadow)    // ambientAndLightCol
 357: mad r19.xyz, r9.xyzx, r8.wwww, -r16.xyzx
 358: mad r16.xyz, r16.wwww, r19.xyzx, r16.xyzx
 359: dp3 r1.w, r16.xyzx, l(0.2127, 0.7152, 0.0722, 0.0000)
 360: add r3.w, -r11.w, l(1.0000)
 361: mad r18.xyz, r18.xyzx, r11.wwww, r3.wwww
 362: mul r16.xyz, r16.xyzx, r18.xyzx
 363: dp3 r3.w, r16.xyzx, l(0.2127, 0.7152, 0.0722, 0.0000)
 364: max r3.w, r3.w, l(0.0010)
 365: rcp r3.w, r3.w
 366: mul r1.w, r1.w, r3.w
 367: max r1.w, r1.w, l(0)
 368: min r1.w, r1.w, l(1.5000) // clamp(0, 1.5, curDiffuseIntensity / max(rampCurDiffuseIntensity, 0.001))            normCurDiffuseIntensity
 369: mad r17.xyz, -r1.xyzx, cb0[160].zzzz, r17.xyzx
 370: mad r15.xzw, r13.wwww, r17.xxyz, r15.xxzw
 371: mad r16.xyz, r16.xyzx, r1.wwww, -r15.xzwx
 372: mad r15.xzw, r6.zzzz, r16.xxyz, r15.xxzw  // lerp(diffuseInSceneShadow, rampCurDiffuseColor * normCurDiffuseIntensity, curSceneShadow)   resultDiffuse
 373: mad r1.w, -r0.w, r15.y, r16.w
 374: mad r1.w, r6.z, r1.w, r13.w       // lerp(camShadowRadiance, rampShadowRadiance, curSceneShadow)    // combineRadiance
 375: mad r3.w, r1.w, l(0.5000), l(0.5000)  // combineRadiance * 0.5 + 0.5
 376: add r10.w, -cb0[160].z, l(1.0000)         // 1 - cb0[160].z  
 377: mad r1.w, r1.w, r10.w, cb0[160].z    // lerp(cb0[160].z, 1, combineRadiance)
 378: mul r1.w, r1.w, r3.w
 379: mul r16.xyz, r1.wwww, r8.xyzx  // (combineRadiance * 0.5 + 0.5) * lerp(cb0[160].z, 1, combineRadiance) * ambientAndLightCol            // ambeintAndLightradiance
 380: add r1.w, r11.y, l(-0.5000)           // lightDir.y - 0.5
 381: mad r17.y, r6.z, r1.w, l(0.5000)    // lerp(0.5, lightDir.y, curSceneShadow)
 382: mov r17.xz, cb0[6].xxzx            // camVector
 383: add r17.xyz, r17.xyzx, r17.xyzx
 384: mad r11.xyz, r11.xyzx, r6.zzzz, r17.xyzx // lightDir * curSceneShadow  + camVector * 2               // shiftLightDir
 385: dp3 r1.w, r11.xyzx, r11.xyzx
 386: max r1.w, r1.w, l(0.0000)
 387: rsq r1.w, r1.w
 388: mad r5.xyz, r11.xyzx, r1.wwww, r5.xyzx   // normalize(halfVector) + viewDirWS       ==> halfDir
 389: dp3 r1.w, r5.xyzx, r5.xyzx             // 
 390: max r1.w, r1.w, l(0.0000)
 391: rsq r1.w, r1.w
 392: mul r5.xyz, r1.wwww, r5.xyzx    // normalize(halfDir)
 393: dp3 r1.w, r2.xywx, r5.xyzx    // // (ndotv)
 394: mul r3.w, r7.y, r7.y             // roughnessSqr * roughnessSqr                  D_GGX(float Roughness, float NoH)
 395: mad r5.x, r1.w, r3.w, -r1.w
 396: mad r1.w, r5.x, r1.w, l(1.0000)
 397: mul r1.w, r1.w, r1.w
 398: ne r5.x, r1.w, r3.w
 399: div r1.w, r3.w, r1.w
 400: movc r1.w, r5.x, r1.w, l(1.0000)
 401: mad r3.w, r7.x, l(2.0000), r7.y
 402: add r3.w, r3.w, l(0.0001)
 403: rcp r3.w, r3.w
 404: mul r1.w, r1.w, r3.w                 // D_GGX / (ndotv*2 + roughnessSqr + 0.0001)           ggxTerm
 405: mad r1.w, r1.w, l(0.5000), l(-0.0001)     
 406: max r1.w, r1.w, l(0)
 407: min r1.w, r1.w, l(20.0000)
 408: mul r5.xyz, r0.xyzx, r1.wwww // specularColor * specularStylizedLUT * min(20, max(ggxTerm * 0.5 - 0.0001, 0))  ==>  specularTerm
 409: mul r5.xyz, r16.xyzx, r5.xyzx          // ambeintAndLightradiance * specularTerm       // ambientAndLightSpecular
 410: mad r5.xyz, r8.xyzx, r15.xzwx, r5.xyzx    //ambientAndLightDiffuse + ambientAndLightSpecular    ambientAndLightDiffuse : ambientAndLightCol * resultDiffuse          // ambientAndLightResultCol
 411: dp3 r1.w, r5.xyzx, l(0.2127, 0.7152, 0.0722, 0.0000)  // ambientAndLightResultColIntensity
 412: add r3.w, r1.w, l(-0.5000)
 413: max r3.w, r3.w, l(0)
 414: min r3.w, r3.w, l(0.5000)
 415: mad r3.w, r3.w, r3.w, l(1.0000) // ambientAndLightIntensity * ambientAndLightIntensity + 1
 416: add r5.xyz, -r1.wwww, r5.xyzx
 417: mad r5.xyz, r3.wwww, r5.xyzx, r1.wwww    // lerp(ambientAndLightResultColIntensity, ambientAndLightResultCol, ambientAndLightIntensity * ambientAndLightIntensity + 1)  //0.5以上的亮度 做一个饱和度调整 ambientAndLightResultCol
 418: lt r1.w, l(0.0100), cb0[168].w            // 0.01 < cb0[168].w    rimLightOn
 419: mul r8.xyz, cb0[6].zxyz, cb0[169].yzxy
 420: mad r8.xyz, cb0[6].yzxy, cb0[169].zxyz, -r8.xyzx  // cross(camVector, cb0[169].xyz)
 421: dp3 r3.w, r8.xyzx, r8.xyzx
 422: max r3.w, r3.w, l(0.0000)
 423: rsq r3.w, r3.w
 424: mul r8.xyz, r3.wwww, r8.xyzx        // camRimDir
 425: add r11.xy, -abs(r5.wwww), l(1.0000, 0.4000, 0.0000, 0.0000)    // (1, 0.4) - abs(ndotv)             // reverseNdotV
 426: mad r11.zw, cb0[167].wwww, l(0.0000, 0.0000, -0.6000, -0.4000), l(0.0000, 0.0000, 0.8000, 0.9000)
 427: add r3.w, -r11.z, r11.w
 428: add r5.w, -r11.z, r11.x
 429: div r3.w, l(1.0000, 1.0000, 1.0000, 1.0000), r3.w
 430: mul_sat r3.w, r3.w, r5.w
 431: mad r5.w, r3.w, l(-2.0000), l(3.0000)
 432: mul r3.w, r3.w, r3.w
 433: mul r3.w, r3.w, r5.w
 434: mul r16.xyz, r3.wwww, cb0[168].xyzx
 435: mul r16.xyz, r16.xyzx, cb0[168].wwww   // cb0[168].wwww * cb0[168].xyz * rimFactor          // rimlight
 436: dp2 r3.w, r3.xyxx, r8.xzxx    // // dot(objectDir, camRimDir.xz)
 437: add_sat r3.w, r3.w, l(1.0000)
 438: min r0.w, r0.w, r3.w
 439: min r0.w, r15.y, r0.w       // min(min(AO, camRimFactor), shadowTex.y)      rimShadow
 440: mul r16.xyz, r0.wwww, r16.xyzx   // rimlight * rimShadow
 441: dp3_sat r0.w, r8.xyzx, r2.xywx   //  saturate(dot(camRimDir, normalTWS))    ndotCamRimDir
 442: mad r8.xyz, r9.xyzx, r8.wwww, l(-0.2500, -0.2500, -0.2500, 0.0000)
 443: mad r8.xyz, cb0[166].wwww, r8.xyzx, l(0.2500, 0.2500, 0.2500, 0.0000)  // lerp(0.25, diffuseColor, cb0[166].w)
 444: mul r8.xyz, r0.wwww, r8.xyzx       // ndotCamRimDir * lerp(0.25, diffuseColor, cb0[166].w)
 445: mul r8.xyz, r8.xyzx, r16.xyzx     // rimlight * rimShadow * ndotCamRimDir * lerp(0.25, diffuseColor, cb0[166].w) rimLightColor
 446: and r8.xyz, r1.wwww, r8.xyzx       // rimLightOn && rimLightColor
 447: dp2 r0.w, cb0[6].xzxx, cb0[6].xzxx   // 
 448: rsq r0.w, r0.w
 449: mul r11.zw, r0.wwww, cb0[6].xxxz     // normalize(camVector.xz)
 450: dp2 r0.w, r7.zwzz, r11.zwzz        //  camDotLXZ
 451: dp2 r1.w, r7.zwzz, r2.xwxx             // ndtolXZ
 452: dp3 r3.w, r13.xyzx, r2.xywx           // ndotDominantSHDir
 453: mul r5.w, r4.w, r3.w                     // dominantOn * ndotDominantSHDir  
 454: mad r7.z, r1.w, l(0.5000), l(-1.0000)   // ndotlXZ * 0.5 - 1
 455: mad r1.w, -r1.w, r7.z, l(0.5000)
 456: mad r1.w, -r3.w, r4.w, r1.w
 457: mad_sat r1.w, r6.z, r1.w, r5.w            // saturate(lerp(ndotDominant, 0.5 - (ndotlXZ * 0.5 - 1) * ndotlXZ, curSceneShadow)   // gEnvRadiance
 458: mul_sat r3.w, r11.y, l(5.0000)         // saturate(reverseNdotV.y * 5)
 459: mad r4.w, r3.w, l(-2.0000), l(3.0000)
 460: mul r3.w, r3.w, r3.w
 461: mul r3.w, r3.w, r4.w
 462: mov_sat r0.w, -r0.w                   // smoothstep(0, 1, saturate(reverseNdotV.y * 5))      reverseRimContrl
 463: add r4.w, -r6.z, l(1.0000)             //  1 - curSceneShadow
 464: mad r0.w, r0.w, r6.z, r4.w           // lerp(1, -camDotLXZ, curSceneShadow)
 465: add r5.w, -cb0[163].w, l(1.0000)   
 466: mul r0.w, r0.w, r5.w           // (1 - cb0[163].w) * lerp(1, -camDotLXZ,curSceneShadow)  // backContorl // 背光控制
 467: add r5.w, r12.w, l(-0.1000)     // diffIntensity - 0.1
 468: mul_sat r5.w, r5.w, l(-16.6667)          // saturate((diffIntensity - 0.1) * -16.6667)   //小于0.1的区域
 469: mad r7.z, r5.w, l(-2.0000), l(3.0000)
 470: mul r5.w, r5.w, r5.w
 471: mul r5.w, r5.w, r7.z
 472: mad r5.w, r5.w, r6.z, r4.w
 473: max r7.z, r12.y, r12.x
 474: max r7.z, r12.z, r7.z
 475: mul r7.z, r7.z, l(0.5000)
 476: max r7.z, r7.z, l(1.0000)         // max(originSHColorMaxComp * 0.5, 1)
 477: rcp r7.z, r7.z 
 478: mul r11.yzw, r7.zzzz, r12.xxyz                  // originSHColor / max(originSHColorMaxComp * 0.5, 1)   // normOriginSHColor
 479: mad r12.xyz, r14.xyzx, r9.wwww, -r11.yzwy
 480: mad r11.yzw, r6.zzzz, r12.xxyz, r11.yyzw      // lerp(normOriginSHColor, lightColor, curSceneShadow)      gEnvColor
 481: max r12.xyz, r10.xyzx, l(0.1500, 0.1500, 0.1500, 0.0000)   // diffuseColor * 0.15
 482: mul r11.yzw, r1.wwww, r11.yyzw
 483: mul r11.yzw, r0.wwww, r11.yyzw
 484: mul r11.yzw, r3.wwww, r11.yyzw
 485: mul r11.yzw, r14.wwww, r11.yyzw
 486: mul r11.yzw, r5.wwww, r11.yyzw    // gEnvColor * gEnvRadiance * backContorl * reverseRimContrl * min(AO, ShadowTex.y) * lerp(1, lowDiffIntensityFactor, curSceneShadow)      gEnvColorR
 487: mad r8.xyz, r11.yzwy, r12.xyzx, r8.xyzx  // diffuseColor * 0.15 * gEnvColorR + rimLightColor              // gEnvDiffuseAndRim
 488: add r5.xyz, r5.xyzx, r8.xyzx              // gEnvDiffuseAndRim + ambientAndLightResultCol
 489: ushr r7.zw, r6.xxxy, l(0, 0, 5, 5)      // screenPos >> 5
 490: imad r0.w, r7.w, cb2[0].w, r7.z   // r4.w * cb2[0].w + r4.x        index
 491: ishl r1.w, r0.w, l(3)                        // r1.z << 3  //index * 8
 492: mad r3.w, -cb0[65].y, cb2[2].w, v9.w    // 深度计算
 493: ftoi r3.w, r3.w
 494: iadd r5.w, r3.w, -cb2[1].y
 495: iadd r5.w, r5.w, l(1)
 496: imax r5.w, r5.w, l(0)
 497: imin r5.w, r5.w, l(1)
 498: iadd r6.z, cb2[1].y, l(-1)       // cb2[1].y - 1
 499: imin r3.w, r3.w, r6.z
 500: ishl r3.w, r3.w, l(3)            // 转换为inidex
 501: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r12.x, r1.w, l(0), t0.xxxx
 502: bfi r13.xyzw, l(29, 29, 29, 29), l(3, 3, 3, 3), r0.wwww, l(1, 2, 3, 4)
 503: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r12.y, r13.x, l(0), t0.xxxx
 504: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r12.z, r13.y, l(0), t0.xxxx
 505: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r12.w, r13.z, l(0), t0.xxxx
 506: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r13.x, r13.w, l(0), t0.xxxx
 507: bfi r8.xyz, l(29, 29, 29, 0), l(3, 3, 3, 0), r0.wwww, l(5, 6, 7, 0)
 508: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r13.y, r8.x, l(0), t0.xxxx
 509: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r13.z, r8.y, l(0), t0.xxxx
 510: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r13.w, r8.z, l(0), t0.xxxx
 511: iadd r0.w, r3.w, cb0[90].y
 512: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r1.w, r0.w, l(0), t0.xxxx
 513: iadd r3.w, -r5.w, l(1)
 514: imul null, r14.x, r1.w, r3.w
 515: iadd r16.xyzw, r0.wwww, l(1, 2, 3, 4)
 516: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r1.w, r16.x, l(0), t0.xxxx
 517: imul null, r14.y, r3.w, r1.w
 518: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r1.w, r16.y, l(0), t0.xxxx
 519: imul null, r14.z, r3.w, r1.w
 520: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r1.w, r16.z, l(0), t0.xxxx
 521: imul null, r14.w, r3.w, r1.w
 522: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r1.w, r16.w, l(0), t0.xxxx
 523: imul null, r16.x, r3.w, r1.w
 524: iadd r8.xyz, r0.wwww, l(5, 6, 7, 0)
 525: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r0.w, r8.x, l(0), t0.xxxx
 526: imul null, r16.y, r3.w, r0.w
 527: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r0.w, r8.y, l(0), t0.xxxx
 528: imul null, r16.z, r3.w, r0.w
 529: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r0.w, r8.z, l(0), t0.xxxx
 530: imul null, r16.w, r3.w, r0.w
 531: and r12.xyzw, r12.xyzw, r14.xyzw
 532: and r13.xyzw, r13.xyzw, r16.xyzw
 533: mov x0[0].x, r12.x
 534: mov x0[1].x, r12.y
 535: mov x0[2].x, r12.z
 536: mov x0[3].x, r12.w
 537: mov x0[4].x, r13.x
 538: mov x0[5].x, r13.y
 539: mov x0[6].x, r13.z
 540: mov x0[7].x, r13.w
 541: ge r0.w, cb5[0].z, l(0.5000)
 542: mad r1.w, r4.w, l(-0.2500), l(0.7500)
 543: mad r8.xyz, r9.xyzx, r8.wwww, l(-0.5000, -0.5000, -0.5000, 0.0000)
 544: and r0.w, r0.w, l(1.0000)
 545: add r3.w, -r7.y, l(0.0100)
 546: mov r9.w, l(1.0000)
 547: mov r12.w, l(1.0000)
 548: mov r11.yzw, r5.xxyz
 549: mov r4.w, l(0)
 550: loop
 551:   ult r5.w, l(7), r4.w
 552:   breakc_nz r5.w
 553:   mov r5.w, x0[r4.w + 0].x
 554:   ishl r6.z, r4.w, l(5)
 555:   mov r13.xyz, r11.yzwy
 556:   mov r7.z, r5.w
 557:   loop
 558:     breakc_z r7.z
 559:     firstbit_lo r7.w, r7.z
 560:     iadd r8.w, r6.z, r7.w
 561:     ishl r7.w, l(1), r7.w
 562:     xor r7.w, r7.w, r7.z
 563:     bfi r14.xyzw, l(29, 29, 29, 29), l(3, 3, 3, 3), r8.wwww, l(1, 5, 6, 7)
 564:     ftou r10.w, cb3[r14.y + 6].w
 565:     ieq r10.w, r10.w, l(1)
 566:     if_nz r10.w
 567:       ushr r16.xyz, cb3[r14.y + 6].xyzx, l(16, 16, 16, 0)
 568:       f16tof32 r17.xyz, cb3[r14.y + 6].xyzx
 569:       f16tof32 r16.xyz, r16.xzyx
 570:       ushr r18.xyz, cb3[r14.z + 6].xyzx, l(16, 16, 16, 0)
 571:       f16tof32 r19.xyz, cb3[r14.z + 6].xyzx
 572:       f16tof32 r18.xyw, r18.xyxz
 573:       add r9.xyz, v1.xyzx, -cb3[r14.x + 6].xyzx
 574:       mov r20.xz, r17.xxyx
 575:       mov r20.yw, r16.xxxz
 576:       dp4 r10.w, r9.xyzw, r20.xyzw
 577:       mov r16.x, r17.z
 578:       mov r16.z, r19.x
 579:       mov r16.w, r18.x
 580:       dp4 r13.w, r9.xyzw, r16.xyzw
 581:       mov r18.xz, r19.yyzy
 582:       dp4 r9.x, r9.xyzw, r18.xyzw
 583:       max r9.y, abs(r10.w), abs(r13.w)
 584:       max r9.x, abs(r9.x), r9.y
 585:       lt r9.y, l(1.0000), r9.x
 586:       if_nz r9.y
 587:         mov r7.z, r7.w
 588:         continue
 589:       endif
 590:       mad r9.y, cb3[r14.w + 6].x, l(0.5000), l(0.5000)
 591:       add r9.x, -r9.y, r9.x
 592:       add r9.y, -r9.y, l(1.0000)
 593:       div_sat r9.x, r9.x, r9.y
 594:       add r9.x, -r9.x, l(1.0000)
 595:       mul r9.x, r9.x, r9.x
 596:     else
 597:       mov r9.x, l(1.0000)
 598:     endif
 599:     ishl r9.y, r8.w, l(3)
 600:     ftou r9.z, cb3[r9.y + 6].w
 601:     ult r10.w, r9.z, l(2)
 602:     if_nz r10.w
 603:       bfi r10.w, l(29), l(3), r8.w, l(3)
 604:       add r13.w, cb0[169].w, cb3[r10.w + 6].z
 605:       lt r13.w, r13.w, l(0.5000)
 606:       ieq r14.y, l(16), cb3[r10.w + 6].w
 607:       or r13.w, r13.w, r14.y
 608:       if_z r13.w
 609:         bfi r16.xy, l(29, 29, 0, 0), l(3, 3, 0, 0), r8.wwww, l(2, 4, 0, 0)
 610:         ieq r8.w, l(4), cb3[r10.w + 6].w
 611:         and r9.z, r9.z, l(1)
 612:         ine r13.w, r9.z, l(0)
 613:         lt r14.y, l(0), cb3[r16.x + 6].z
 614:         and r13.w, r13.w, r14.y
 615:         mad r14.y, cb3[r16.x + 6].y, l(0.5000), l(0.5000)
 616:         add r17.z, r14.y, -abs(cb3[r16.x + 6].x)
 617:         add r17.x, -r17.z, cb3[r16.x + 6].y
 618:         add r14.y, -abs(r17.z), l(1.0000)
 619:         add r14.y, -abs(r17.x), r14.y
 620:         max r14.y, r14.y, l(0.0000)
 621:         ge r15.y, cb3[r16.x + 6].x, l(0)
 622:         movc r17.y, r15.y, r14.y, -r14.y
 623:         dp3 r14.y, r17.xyzx, r17.xyzx
 624:         rsq r14.y, r14.y
 625:         mul r17.xyz, r14.yyyy, r17.xyzx
 626:         lt r14.y, l(0.5000), cb3[r16.y + 6].z
 627:         and r14.y, r8.w, r14.y
 628:         add r18.xyz, -v1.xyzx, cb3[r14.x + 6].xyzx
 629:         dp3 r15.y, r18.yzxy, -r17.xyzx
 630:         and r14.y, r14.y, l(1.0000)
 631:         movc r14.y, r9.z, l(0), r14.y
 632:         mad r19.xyz, r15.yyyy, -r17.zxyz, -r18.xyzx
 633:         mad r18.xyz, r14.yyyy, r19.xyzx, r18.xyzx
 634:         dp3 r14.y, r18.xyzx, r18.xyzx
 635:         rsq r15.y, r14.y
 636:         mul r12.xyz, r15.yyyy, r18.xyzx
 637:         add r15.y, cb3[r16.y + 6].y, cb3[r16.y + 6].y
 638:         max r15.y, r15.y, l(0.1000)
 639:         movc r14.z, r8.w, r15.y, cb3[r14.z + 6].w
 640:         mul r19.xyz, r17.zxyz, cb3[r16.x + 6].zzzz
 641:         mad r20.xyz, -r19.xyzx, l(0.5000, 0.5000, 0.5000, 0.0000), r18.xyzx
 642:         mad r19.xyz, r19.xyzx, l(0.5000, 0.5000, 0.5000, 0.0000), r18.xyzx
 643:         dp3 r15.y, r20.xyzx, r20.xyzx
 644:         sqrt r15.y, r15.y
 645:         dp3 r16.z, r19.xyzx, r19.xyzx
 646:         sqrt r16.z, r16.z
 647:         dp3 r16.w, r20.xyzx, r19.xyzx
 648:         mad r16.w, r15.y, r16.z, r16.w
 649:         mad r16.w, r16.w, l(0.5000), l(1.0000)
 650:         rcp r16.w, r16.w
 651:         mul r21.xyz, r12.xyzx, r17.xyzx
 652:         mad r21.xyz, r17.zxyz, r12.yzxy, -r21.xyzx
 653:         dp3 r17.w, r21.xyzx, r21.xyzx
 654:         rsq r17.w, r17.w
 655:         mul r21.xyz, r17.wwww, r21.xyzx
 656:         mul r22.xyz, r17.xyzx, r21.xyzx
 657:         mad r21.xyz, r21.zxyz, r17.yzxy, -r22.xyzx
 658:         dp3 r17.w, r21.xyzx, r21.xyzx
 659:         rsq r17.w, r17.w
 660:         mul r21.xyz, r17.wwww, r21.xyzx
 661:         dp3 r17.w, r21.xyzx, r20.xyzx
 662:         div r15.y, r17.w, r15.y
 663:         dp3 r17.w, r21.xyzx, r19.xyzx
 664:         div r16.z, r17.w, r16.z
 665:         add r15.y, r15.y, r16.z
 666:         mul_sat r15.y, r15.y, l(0.5000)
 667:         mul r21.w, r15.y, r16.w
 668:         movc r19.xyzw, r13.wwww, r21.xyzw, r12.xyzw
 669:         lt r12.x, r14.z, l(0)
 670:         add r12.y, r14.y, l(1.0000)
 671:         div r12.y, l(1.0000, 1.0000, 1.0000, 1.0000), r12.y
 672:         and r12.z, r13.w, l(1.0000)
 673:         add r13.w, -r12.y, r19.w
 674:         mad r12.y, r12.z, r13.w, r12.y
 675:         mul r12.z, cb3[r14.x + 6].w, cb3[r14.x + 6].w
 676:         mul r12.z, r12.z, r14.y
 677:         mad r12.z, -r12.z, r12.z, l(1.0000)
 678:         max r12.z, r12.z, l(0)
 679:         mul r12.z, r12.z, r12.z
 680:         mul r12.y, r12.z, r12.y
 681:         mul r18.xyz, r18.xyzx, cb3[r14.x + 6].wwww
 682:         dp3 r12.z, r18.xyzx, r18.xyzx
 683:         min r12.z, r12.z, l(1.0000)
 684:         add r12.z, -r12.z, l(1.0000)
 685:         log r12.z, r12.z
 686:         mul r12.z, r12.z, r14.z
 687:         exp r12.z, r12.z
 688:         mul r12.z, r12.z, r19.w
 689:         movc r12.x, r12.x, r12.y, r12.z
 690:         dp3 r12.y, r19.yzxy, -r17.xyzx
 691:         add r12.y, r12.y, -cb3[r16.x + 6].z
 692:         mul_sat r12.y, r12.y, cb3[r16.x + 6].w
 693:         mul r12.y, r12.y, r12.y
 694:         mul r12.y, r12.y, r12.x
 695:         movc r12.x, r9.z, r12.x, r12.y
 696:         mul r9.x, r9.x, r12.x
 697:         lt r12.x, l(0), r9.x
 698:         if_nz r12.x
 699:           if_nz r8.w
 700:             dp3 r12.x, r4.xyzx, r19.xyzx
 701:             add_sat r12.x, r12.x, l(0.5000)
 702:             mad r12.y, r12.x, l(-2.0000), l(3.0000)
 703:             mul r12.x, r12.x, r12.x
 704:             mul r12.x, r12.x, r12.y
 705:             add r12.y, l(1.0000), -cb3[r16.y + 6].w
 706:             mad r12.x, r12.x, cb3[r16.y + 6].w, r12.y
 707:             mul r12.x, r12.x, cb3[r16.y + 6].x
 708:             mul r12.x, r9.x, r12.x
 709:             add r17.xyz, -r13.xyzx, cb3[r9.y + 6].xyzx
 710:             mad r13.xyz, r12.xxxx, r17.xyzx, r13.xyzx
 711:             mov r12.xyz, r13.xyzx
 712:           else
 713:             mov r12.xyz, r13.xyzx
 714:           endif
 715:           if_z r8.w
 716:             ieq r14.yz, l(0, 1, 3, 0), cb3[r10.w + 6].wwww
 717:             if_z cb3[r10.w + 6].w
 718:               mul r17.xyz, r9.xxxx, cb3[r9.y + 6].xyzx
 719:               max r13.w, r17.y, r17.x
 720:               max r13.w, r17.z, r13.w
 721:               mul r13.w, r1.w, r13.w
 722:               max r13.w, r13.w, l(1.0000)
 723:               rcp r13.w, r13.w
 724:               add r15.y, l(1.0000), -cb3[r16.y + 6].y
 725:               mad r13.w, r13.w, cb3[r16.y + 6].y, r15.y
 726:               mul r17.xyz, r13.wwww, cb3[r9.y + 6].xyzx
 727:               mul r13.w, l(0.5000), cb3[r16.y + 6].x
 728:               dp3 r15.y, r2.xywx, r19.xyzx
 729:               add_sat r15.y, r15.y, l(0.5000)
 730:               mad r16.z, -cb3[r16.y + 6].x, l(0.5000), l(1.0000)
 731:               mad r13.w, r15.y, r16.z, r13.w
 732:               mul r17.xyz, r13.wwww, r17.xyzx
 733:               mov r18.xyz, r15.xzwx
 734:               mov r20.xyz, r15.xzwx
 735:               mov r13.w, l(1.0000)
 736:             else
 737:               ftoi r15.y, cb3[r10.w + 6].x
 738:               add r21.xyz, v1.xyzx, -cb3[r14.x + 6].xyzx
 739:               lt r22.xyz, abs(r21.yzzy), abs(r21.xxyx)
 740:               and r14.x, r22.y, r22.x
 741:               lt r22.xyw, l(0, 0, 0, 0), r21.xyxz
 742:               ushr r16.z, cb3[r16.x + 6].w, l(24)
 743:               ubfe r23.xy, l(8, 8, 0, 0), l(16, 8, 0, 0), cb3[r16.x + 6].wwww
 744:               movc r16.z, r22.x, r16.z, r23.x
 745:               and r16.x, l(255), cb3[r16.x + 6].w
 746:               movc r16.x, r22.y, r23.y, r16.x
 747:               ubfe r16.w, l(8), l(8), cb3[r10.w + 6].x
 748:               and r17.w, l(255), cb3[r10.w + 6].x
 749:               movc r16.w, r22.w, r16.w, r17.w
 750:               movc r16.x, r22.z, r16.x, r16.w
 751:               movc r14.x, r14.x, r16.z, r16.x
 752:               ilt r16.x, r14.x, l(80)
 753:               movc r14.x, r16.x, r14.x, l(-1)
 754:               movc r9.z, r9.z, r14.x, r15.y
 755:               ige r14.x, r9.z, l(0)
 756:               if_nz r14.x
 757:                 dp3 r14.x, r21.xyzx, r21.xyzx
 758:                 max r14.x, r14.x, l(0.0000)
 759:                 rsq r14.x, r14.x
 760:                 mul r16.xzw, r14.xxxx, r21.xxyz
 761:                 dp3 r14.x, r4.xyzx, r16.xzwx
 762:                 max r14.x, r14.x, l(0)
 763:                 min r14.x, r14.x, l(0.9000)
 764:                 add r14.x, -r14.x, l(1.0000)
 765:                 mul r21.xy, r14.xxxx, cb4[r9.z + 256].xyxx
 766:                 mul r14.x, r21.y, l(5.0000)
 767:                 mad r16.xzw, -r16.xxzw, r21.xxxx, v1.xxyz
 768:                 mad r16.xzw, r4.xxyz, r14.xxxx, r16.xxzw
 769:                 ishl r14.x, r9.z, l(2)
 770:                 mul r21.xyzw, r16.zzzz, cb4[r14.x + 33].xyzw
 771:                 mad r21.xyzw, cb4[r14.x + 32].xyzw, r16.xxxx, r21.xyzw
 772:                 mad r21.xyzw, cb4[r14.x + 34].xyzw, r16.wwww, r21.xyzw
 773:                 add r21.xyzw, r21.xyzw, cb4[r14.x + 35].xyzw
 774:                 div r16.xzw, r21.xxyz, r21.wwww
 775:                 add r21.xy, -cb4[r9.z + 312].xyxx, cb4[r9.z + 312].zwzz
 776:                 mad r21.xy, r16.xzxx, r21.xyxx, cb4[r9.z + 312].xyxx
 777:                 ge r22.xyz, l(0, 0, 0, 0), r16.xzwx
 778:                 ge r23.xyz, r16.xzwx, l(1.0000, 1.0000, 1.0000, 0.0000)
 779:                 or r22.xyz, r22.xyzx, r23.xyzx
 780:                 or r14.x, r22.y, r22.x
 781:                 or r14.x, r22.z, r14.x
 782:                 and r15.y, r16.w, l(0x7fffffff)
 783:                 ult r15.y, l(0x7f800000), r15.y
 784:                 or r14.x, r14.x, r15.y
 785:                 mad r16.xz, r21.xxyx, cb4[368].zzwz, l(0.5000, 0.0000, 0.5000, 0.0000)
 786:                 round_ni r16.xz, r16.xxzx
 787:                 mad r21.xy, r21.xyxx, cb4[368].zwzz, -r16.xzxx
 788:                 add r22.xyzw, r21.xxyy, l(0.5000, 1.0000, 0.5000, 1.0000)
 789:                 mul r23.xyzw, r22.xxzz, r22.xxzz
 790:                 mul r21.zw, r23.yyyw, l(0.0000, 0.0000, 0.0800, 0.0800)
 791:                 mad r22.xz, r23.xxzx, l(0.5000, 0.0000, 0.5000, 0.0000), -r21.xxyx
 792:                 add r23.xy, -r21.xyxx, l(1.0000, 1.0000, 0.0000, 0.0000)
 793:                 min r23.zw, r21.xxxy, l(0, 0, 0, 0)
 794:                 mad r23.zw, -r23.zzzw, r23.zzzw, r23.xxxy
 795:                 max r21.xy, r21.xyxx, l(0, 0, 0, 0)
 796:                 mad r21.xy, -r21.xyxx, r21.xyxx, r22.ywyy
 797:                 add r23.zw, r23.zzzw, l(0.0000, 0.0000, 1.0000, 1.0000)
 798:                 add r21.xy, r21.xyxx, l(1.0000, 1.0000, 0.0000, 0.0000)
 799:                 mul r24.xy, r22.xzxx, l(0.1600, 0.1600, 0.0000, 0.0000)
 800:                 mul r25.xy, r23.xyxx, l(0.1600, 0.1600, 0.0000, 0.0000)
 801:                 mul r23.xy, r23.zwzz, l(0.1600, 0.1600, 0.0000, 0.0000)
 802:                 mul r26.xy, r21.xyxx, l(0.1600, 0.1600, 0.0000, 0.0000)
 803:                 mul r21.xy, r22.ywyy, l(0.1600, 0.1600, 0.0000, 0.0000)
 804:                 mov r24.z, r23.x
 805:                 mov r24.w, r21.x
 806:                 mov r25.z, r26.x
 807:                 mov r25.w, r21.z
 808:                 add r22.xyzw, r24.zwxz, r25.zwxz
 809:                 mov r23.z, r24.y
 810:                 mov r23.w, r21.y
 811:                 mov r26.z, r25.y
 812:                 mov r26.w, r21.w
 813:                 add r21.xyz, r23.zywz, r26.zywz
 814:                 div r23.xyz, r25.xzwx, r22.zwyz
 815:                 add r23.xyz, r23.xyzx, l(-2.5000, -0.5000, 1.5000, 0.0000)
 816:                 div r24.xyz, r26.zywz, r21.xyzx
 817:                 add r24.xyz, r24.xyzx, l(-2.5000, -0.5000, 1.5000, 0.0000)
 818:                 mul r23.xyz, r23.yxzy, cb4[368].xxxx
 819:                 mul r24.xyz, r24.xyzx, cb4[368].yyyy
 820:                 mov r23.w, r24.x
 821:                 mad r25.xyzw, r16.xzxz, cb4[368].xyxy, r23.ywxw
 822:                 mad r26.xy, r16.xzxx, cb4[368].xyxx, r23.zwzz
 823:                 mov r24.w, r23.y
 824:                 mov r23.yw, r24.yyyz
 825:                 mad r27.xyzw, r16.xzxz, cb4[368].xyxy, r23.xyzy
 826:                 mad r24.xyzw, r16.xzxz, cb4[368].xyxy, r24.wywz
 827:                 mad r23.xyzw, r16.xzxz, cb4[368].xyxy, r23.xwzw
 828:                 mul r28.xyzw, r21.xxxy, r22.zwyz
 829:                 mul r29.xyzw, r21.yyzz, r22.xyzw
 830:                 mul r15.y, r21.z, r22.y
 831:                 sample_c_lz(texture2d)(float,float,float,float) r16.x, r25.xyxx, t1.xxxx, s2, r16.w
 832:                 sample_c_lz(texture2d)(float,float,float,float) r16.z, r25.zwzz, t1.xxxx, s2, r16.w
 833:                 mul r16.z, r16.z, r28.y
 834:                 mad r16.x, r28.x, r16.x, r16.z
 835:                 sample_c_lz(texture2d)(float,float,float,float) r16.z, r26.xyxx, t1.xxxx, s2, r16.w
 836:                 mad r16.x, r28.z, r16.z, r16.x
 837:                 sample_c_lz(texture2d)(float,float,float,float) r16.z, r24.xyxx, t1.xxxx, s2, r16.w
 838:                 mad r16.x, r28.w, r16.z, r16.x
 839:                 sample_c_lz(texture2d)(float,float,float,float) r16.z, r27.xyxx, t1.xxxx, s2, r16.w
 840:                 mad r16.x, r29.x, r16.z, r16.x
 841:                 sample_c_lz(texture2d)(float,float,float,float) r16.z, r27.zwzz, t1.xxxx, s2, r16.w
 842:                 mad r16.x, r29.y, r16.z, r16.x
 843:                 sample_c_lz(texture2d)(float,float,float,float) r16.z, r24.zwzz, t1.xxxx, s2, r16.w
 844:                 mad r16.x, r29.z, r16.z, r16.x
 845:                 sample_c_lz(texture2d)(float,float,float,float) r16.z, r23.xyxx, t1.xxxx, s2, r16.w
 846:                 mad r16.x, r29.w, r16.z, r16.x
 847:                 sample_c_lz(texture2d)(float,float,float,float) r16.z, r23.zwzz, t1.xxxx, s2, r16.w
 848:                 mad r15.y, r15.y, r16.z, r16.x
 849:                 add r15.y, r15.y, l(-1.0000)
 850:                 mad r9.z, cb4[r9.z + 256].w, r15.y, l(1.0000)
 851:                 movc r13.w, r14.x, l(1.0000), r9.z
 852:               else
 853:                 dp2 r9.z, r3.xyxx, r19.xzxx
 854:                 add_sat r13.w, r9.z, l(1.0000)
 855:               endif
 856:               mov r17.xyz, cb3[r9.y + 6].xyzx
 857:               mov r18.xyz, l(0, 0, 0, 0)
 858:               mov r20.xyz, l(0, 0, 0, 0)
 859:             endif
 860:             dp3 r9.y, r2.xywx, r19.xyzx
 861:             if_nz r14.y
 862:               add r9.z, r9.y, cb3[r16.y + 6].x
 863:               max_sat r9.z, r9.z, l(-1.0000)
 864:               mul r9.y, r13.w, r9.z
 865:               mul r20.xyz, r1.xyzx, cb3[r16.y + 6].yyyy
 866:               mov r18.xyz, r10.xyzx
 867:             else
 868:               mov_sat r9.y, r9.y
 869:             endif
 870:             if_nz r14.z
 871:               mul r16.xzw, r19.zzxy, cb0[6].xxyz
 872:               mad r16.xzw, cb0[6].zzxy, r19.xxyz, -r16.xxzw
 873:               mul r21.xyz, r16.xzwx, cb0[6].zxyz
 874:               mad r16.xzw, cb0[6].yyzx, r16.zzwx, -r21.xxyz
 875:               dp3 r9.z, r16.xzwx, r16.xzwx
 876:               rsq r9.z, r9.z
 877:               mul r16.xzw, r9.zzzz, r16.xxzw
 878:               dp3_sat r9.y, r2.xywx, -r16.xzwx
 879:               mad r14.xy, cb3[r16.y + 6].xxxx, l(-0.6000, -0.4000, 0.0000, 0.0000), l(0.8000, 0.9000, 0.0000, 0.0000)
 880:               add r9.z, -r14.x, r14.y
 881:               add r14.x, r11.x, -r14.x
 882:               div r9.z, l(1.0000, 1.0000, 1.0000, 1.0000), r9.z
 883:               mul_sat r9.z, r9.z, r14.x
 884:               mad r14.x, r9.z, l(-2.0000), l(3.0000)
 885:               mul r9.z, r9.z, r9.z
 886:               mul r9.z, r9.z, r14.x
 887:               mul r9.z, r13.w, r9.z
 888:               mul r9.x, r9.z, r9.x
 889:               mad r18.xyz, cb3[r16.y + 6].yyyy, r8.xyzx, l(0.5000, 0.5000, 0.5000, 0.0000)
 890:               mov r20.xyz, l(0, 0, 0, 0)
 891:             endif
 892:             if_z r14.z
 893:               ieq r9.z, l(2), cb3[r10.w + 6].w
 894:               add r10.w, l(0.0500), cb3[r16.y + 6].x
 895:               add r10.w, r2.z, -r10.w
 896:               mul_sat r10.w, r10.w, l(-10.0000)
 897:               mad r13.w, r10.w, l(-2.0000), l(3.0000)
 898:               mul r10.w, r10.w, r10.w
 899:               mul r10.w, r10.w, r13.w
 900:               add r13.w, l(1.0000), -cb3[r16.y + 6].z
 901:               mad r13.w, r0.w, cb3[r16.y + 6].z, r13.w
 902:               mul r14.x, r10.w, r13.w
 903:               mov r14.y, cb3[r16.y + 6].y
 904:               movc r14.xy, r9.zzzz, r14.xyxx, l(1.0000, 0.0000, 0.0000, 0.0000)
 905:               mad r9.z, r14.y, r3.w, r7.y
 906:               mad r16.xyz, v4.xyzx, r3.zzzz, r19.xyzx
 907:               dp3 r10.w, r16.xyzx, r16.xyzx
 908:               max r10.w, r10.w, l(0.0000)
 909:               rsq r10.w, r10.w
 910:               mul r16.xyz, r10.wwww, r16.xyzx
 911:               dp3 r10.w, r2.xywx, r16.xyzx
 912:               mul r13.w, r9.z, r9.z
 913:               mad r14.y, r10.w, r13.w, -r10.w
 914:               mad r10.w, r14.y, r10.w, l(1.0000)
 915:               mul r10.w, r10.w, r10.w
 916:               ne r14.y, r10.w, r13.w
 917:               div r10.w, r13.w, r10.w
 918:               movc r10.w, r14.y, r10.w, l(1.0000)
 919:               mad r9.z, r7.x, l(2.0000), r9.z
 920:               add r9.z, r9.z, l(0.0001)
 921:               rcp r9.z, r9.z
 922:               mul r9.z, r9.z, r10.w
 923:               mad r9.z, r9.z, l(0.5000), l(-0.0001)
 924:               max r9.z, r9.z, l(0)
 925:               min r9.z, r9.z, l(100.0000)
 926:               mul r16.xyz, r0.xyzx, r9.zzzz
 927:               mul r14.xyz, r14.xxxx, r16.xyzx
 928:               mul r14.xyz, r14.xyzx, cb3[r14.w + 6].zzzz
 929:             else
 930:               mov r14.xyz, l(0, 0, 0, 0)
 931:             endif
 932:             add r16.xyz, r18.xyzx, -r20.xyzx
 933:             mad r16.xyz, r9.yyyy, r16.xyzx, r20.xyzx
 934:             mul r17.xyz, r17.xyzx, r9.xxxx
 935:             mul r14.xyz, r14.xyzx, r17.xyzx
 936:             mul r9.xyz, r9.yyyy, r14.xyzx
 937:             mad r9.xyz, r17.xyzx, r16.xyzx, r9.xyzx
 938:             add r13.xyz, r9.xyzx, r13.xyzx
 939:           endif
 940:         else
 941:           mov r12.xyz, r13.xyzx
 942:           mov r8.w, l(0)
 943:         endif
 944:         movc r13.xyz, r8.wwww, r12.xyzx, r13.xyzx
 945:       endif
 946:     endif
 947:     mov r7.z, r7.w
 948:   endloop
 949:   mov r11.yzw, r13.xxyz
 950:   iadd r4.w, r4.w, l(1)
 951: endloop
 952: div r0.xyz, r11.yzwy, cb0[89].xxxx
 953: lt r0.w, cb0[171].w, l(0.5000)
 954: if_nz r0.w
 955:   eq r0.w, cb0[66].w, l(0)
 956:   add r1.xyz, -v1.xyzx, cb0[32].xyzx
 957:   mov r2.x, cb0[0].z
 958:   mov r2.y, cb0[1].z
 959:   mov r2.z, cb0[2].z
 960:   movc r1.xyz, r0.wwww, r1.xyzx, r2.xyzx
 961:   dp3 r0.w, r1.xyzx, r1.xyzx
 962:   sqrt r1.w, r0.w
 963:   mad r1.w, r1.w, cb0[136].w, -cb0[134].w
 964:   max r1.w, r1.w, l(0)
 965:   add r2.w, -cb0[133].w, cb0[135].w
 966:   mad r3.x, v1.y, l(0.0010), -cb0[133].w
 967:   rsq r0.w, r0.w
 968:   mul r1.xyz, r0.wwww, r1.xyzx
 969:   dp3 r0.w, -r1.xyzx, cb0[136].xyzx
 970:   add r3.yzw, cb0[132].xxyz, cb0[134].xxyz
 971:   add r4.xyz, r3.yzwy, cb0[133].xyzx
 972:   add r2.w, r2.w, -r3.x
 973:   div r2.w, r2.w, cb0[131].w
 974:   max r2.w, r2.w, l(0.0100)
 975:   mul r4.w, r2.w, l(-1.4427)
 976:   exp r4.w, r4.w
 977:   add r4.w, -r4.w, l(1.0000)
 978:   div r2.w, r4.w, r2.w
 979:   div r3.x, -r3.x, cb0[131].w
 980:   mul r3.x, r3.x, l(1.4427)
 981:   exp r3.x, r3.x
 982:   mul r2.w, r2.w, r3.x
 983:   mul r1.w, -r1.w, r2.w
 984:   mul r5.xyz, r4.xyzx, r1.wwww
 985:   mul r5.xyz, r5.xyzx, l(1.4427, 1.4427, 1.4427, 0.0000)
 986:   exp r5.xyz, r5.xyzx
 987:   mad r1.w, r0.w, r0.w, l(1.0000)
 988:   mul r1.w, r1.w, l(0.0597)
 989:   mad r2.w, cb0[132].w, cb0[132].w, l(1.0000)
 990:   add r3.x, cb0[132].w, cb0[132].w
 991:   mad r0.w, -r3.x, r0.w, r2.w
 992:   mad r2.w, -cb0[132].w, cb0[132].w, l(1.0000)
 993:   mul r3.x, r0.w, l(12.5664)
 994:   sqrt r0.w, r0.w
 995:   mul r0.w, r0.w, r3.x
 996:   div r0.w, r2.w, r0.w
 997:   mul r7.xyz, r0.wwww, cb0[132].xyzx
 998:   mad r7.xyz, cb0[134].xyzx, r1.wwww, r7.xyzx
 999:   mul r3.xyz, r3.yzwy, cb0[135].xyzx
1000:   mad r3.xyz, cb0[131].xyzx, r7.xyzx, r3.xyzx
1001:   div r3.xyz, r3.xyzx, r4.xyzx
1002:   max r3.xyz, r3.xyzx, l(0, 0, 0, 0)
1003:   min r3.xyz, r3.xyzx, l(255.0000, 255.0000, 255.0000, 0.0000)
1004:   add r4.xyz, -r5.xyzx, l(1.0000, 1.0000, 1.0000, 0.0000)
1005:   mul r3.xyz, r3.xyzx, r4.xyzx
1006:   mad r3.xyz, r0.xyzx, r5.xyzx, r3.xyzx
1007:   lt r0.w, l(0), cb0[141].z
1008:   if_nz r0.w
1009:     mad r0.w, v9.w, cb0[142].x, cb0[142].y
1010:     log r0.w, r0.w
1011:     mul r0.w, r0.w, cb0[142].z
1012:     div r4.z, r0.w, cb0[141].z
1013:     and r6.w, cb0[88].w, l(7)
1014:     imad r5.xyz, r6.xywx, l(0x0019660d, 0x0019660d, 0x0019660d, 0), l(0.0146, 0.0146, 0.0146, 0.0000)
1015:     imad r0.w, r5.y, r5.z, r5.x
1016:     imad r1.w, r5.z, r0.w, r5.y
1017:     imad r2.w, r0.w, r1.w, r5.z
1018:     imad r5.x, r1.w, r2.w, r0.w
1019:     imad r5.y, r2.w, r5.x, r1.w
1020:     ushr r5.xy, r5.xyxx, l(16, 16, 0, 0)
1021:     utof r5.xy, r5.xyxx
1022:     mad r5.xy, r5.xyxx, l(0.0000, 0.0000, 0.0000, 0.0000), l(-1.0000, -1.0000, 0.0000, 0.0000)
1023:     utof r5.zw, r6.xxxy
1024:     mad r5.xy, cb0[145].wwww, r5.xyxx, r5.zwzz
1025:     mul r4.xy, r5.xyxx, cb0[143].xyxx
1026:     dp3 r0.w, -r1.xyzx, -r2.xyzx
1027:     lt r1.x, l(0.0000), r0.w
1028:     rcp r0.w, r0.w
1029:     and r0.w, r0.w, r1.x
1030:     mul r0.w, r0.w, cb0[141].w
1031:     add r1.xyz, v1.xyzx, -cb0[32].xyzx
1032:     dp3 r1.x, r1.xyzx, r1.xyzx
1033:     max r1.z, r1.x, l(0.0000)
1034:     rsq r1.z, r1.z
1035:     mul r1.w, r1.z, r1.x
1036:     mul r2.x, r0.w, r1.z
1037:     mad r2.y, r2.x, r1.y, cb0[32].y
1038:     mad r1.y, -r2.x, r1.y, r1.y
1039:     mad r0.w, -r0.w, r1.z, l(1.0000)
1040:     mul r0.w, r1.w, r0.w
1041:     add r1.w, r2.y, -cb0[137].x
1042:     mul r1.w, r1.w, cb0[137].z
1043:     max r1.w, r1.w, l(-127.0000)
1044:     exp r1.w, -r1.w
1045:     mul r1.w, r1.w, cb0[137].y
1046:     mul r2.x, r1.y, cb0[137].z
1047:     max r2.x, r2.x, l(-127.0000)
1048:     exp r2.z, -r2.x
1049:     add r2.z, -r2.z, l(1.0000)
1050:     div r2.z, r2.z, r2.x
1051:     mad r2.w, -r2.x, l(0.2402), l(0.6931)
1052:     lt r2.x, l(0.0000), abs(r2.x)
1053:     movc r2.x, r2.x, r2.z, r2.w
1054:     mul r1.w, r1.w, r2.x
1055:     lt r2.x, l(0), cb0[140].y
1056:     add r2.y, r2.y, -cb0[140].z
1057:     mul r2.y, r2.y, cb0[140].x
1058:     max r2.y, r2.y, l(-127.0000)
1059:     exp r2.y, -r2.y
1060:     mul r2.y, r2.y, cb0[140].y
1061:     mul r1.y, r1.y, cb0[140].x
1062:     max r1.y, r1.y, l(-127.0000)
1063:     exp r2.z, -r1.y
1064:     add r2.z, -r2.z, l(1.0000)
1065:     div r2.z, r2.z, r1.y
1066:     mad r2.w, -r1.y, l(0.2402), l(0.6931)
1067:     lt r1.y, l(0.0000), abs(r1.y)
1068:     movc r1.y, r1.y, r2.z, r2.w
1069:     mad r1.y, r2.y, r1.y, r1.w
1070:     movc r1.y, r2.x, r1.y, r1.w
1071:     mul r0.w, r0.w, r1.y
1072:     exp r0.w, -r0.w
1073:     min r0.w, r0.w, l(1.0000)
1074:     max r0.w, r0.w, cb0[139].w
1075:     mad r1.y, -r1.x, r1.z, cb0[138].x
1076:     mad r1.x, r1.x, r1.z, -cb0[138].z
1077:     mul_sat r1.xy, r1.xyxx, cb0[138].wyww
1078:     add r0.w, r0.w, r1.y
1079:     add r0.w, r1.x, r0.w
1080:     min r0.w, r0.w, l(1.0000)
1081:     add r1.x, -r0.w, l(1.0000)
1082:     mul r1.xyz, r1.xxxx, cb0[139].xyzx
1083:     sample_l(texture3d)(float,float,float,float) r2.xyzw, r4.xyzx, t11.xyzw, s1, l(0)
1084:     add r1.w, v9.w, -cb0[144].z
1085:     mul_sat r1.w, r1.w, l(1000000.0000)
1086:     add r2.xyzw, r2.xyzw, l(-0.0000, -0.0000, -0.0000, -1.0000)
1087:     mad r2.xyzw, r1.wwww, r2.xyzw, l(0.0000, 0.0000, 0.0000, 1.0000)
1088:     mad r1.xyz, r1.xyzx, r2.wwww, r2.xyzx
1089:     mul r0.w, r0.w, r2.w
1090:   else
1091:     add r2.xyz, v1.xyzx, -cb0[32].xyzx
1092:     dp3 r1.w, r2.xyzx, r2.xyzx
1093:     max r2.x, r1.w, l(0.0000)
1094:     rsq r2.x, r2.x
1095:     mul r2.z, r1.w, r2.x
1096:     add r2.w, cb0[32].y, -cb0[137].x
1097:     mul r2.w, r2.w, cb0[137].z
1098:     max r2.w, r2.w, l(-127.0000)
1099:     exp r2.w, -r2.w
1100:     mul r2.w, r2.w, cb0[137].y
1101:     mul r3.w, r2.y, cb0[137].z
1102:     max r3.w, r3.w, l(-127.0000)
1103:     exp r4.x, -r3.w
1104:     add r4.x, -r4.x, l(1.0000)
1105:     div r4.x, r4.x, r3.w
1106:     mad r4.y, -r3.w, l(0.2402), l(0.6931)
1107:     lt r3.w, l(0.0000), abs(r3.w)
1108:     movc r3.w, r3.w, r4.x, r4.y
1109:     mul r2.w, r2.w, r3.w
1110:     lt r3.w, l(0), cb0[140].y
1111:     add r4.x, cb0[32].y, -cb0[140].z
1112:     mul r4.x, r4.x, cb0[140].x
1113:     max r4.x, r4.x, l(-127.0000)
1114:     exp r4.x, -r4.x
1115:     mul r4.x, r4.x, cb0[140].y
1116:     mul r2.y, r2.y, cb0[140].x
1117:     max r2.y, r2.y, l(-127.0000)
1118:     exp r4.y, -r2.y
1119:     add r4.y, -r4.y, l(1.0000)
1120:     div r4.y, r4.y, r2.y
1121:     mad r4.z, -r2.y, l(0.2402), l(0.6931)
1122:     lt r2.y, l(0.0000), abs(r2.y)
1123:     movc r2.y, r2.y, r4.y, r4.z
1124:     mad r2.y, r4.x, r2.y, r2.w
1125:     movc r2.y, r3.w, r2.y, r2.w
1126:     mul r2.y, r2.z, r2.y
1127:     exp r2.y, -r2.y
1128:     min r2.y, r2.y, l(1.0000)
1129:     max r2.y, r2.y, cb0[139].w
1130:     mad r2.z, -r1.w, r2.x, cb0[138].x
1131:     mul_sat r2.z, r2.z, cb0[138].y
1132:     mad r1.w, r1.w, r2.x, -cb0[138].z
1133:     mul_sat r1.w, r1.w, cb0[138].w
1134:     add r2.x, r2.z, r2.y
1135:     add r1.w, r1.w, r2.x
1136:     min r0.w, r1.w, l(1.0000)
1137:     add r1.w, -r0.w, l(1.0000)
1138:     mul r1.xyz, r1.wwww, cb0[139].xyzx
1139:   endif
1140:   mad r0.xyz, r3.xyzx, r0.wwww, r1.xyzx
1141: endif
1142: max r0.w, v5.z, l(0.0000)
1143: div r1.xy, v5.xyxx, r0.wwww
1144: max r0.w, v6.z, l(0.0000)
1145: div r1.zw, v6.xxxy, r0.wwww
1146: add r1.xy, -r1.zwzz, r1.xyxx
1147: mul r2.xy, r1.xyxx, l(0.5000, -0.5000, 0.0000, 0.0000)
1148: sqrt r2.xy, abs(r2.xyxx)
1149: mov r1.z, -r1.y
1150: lt r1.yw, l(0, 0, 0, 0), r1.xxxz
1151: lt r1.xz, r1.xxzx, l(0, 0, 0, 0)
1152: iadd r1.xy, -r1.ywyy, r1.xzxx
1153: itof r1.xy, r1.xyxx
1154: mul r1.xy, r1.xyxx, r2.xyxx
1155: mad o1.xy, r1.xyxx, l(0.5000, 0.5000, 0.0000, 0.0000), l(0.5000, 0.5000, 0.0000, 0.0000)
1156: mov o0.xyz, r0.xyzx
1157: mov o0.w, l(1.0000)
1158: mov o1.zw, l(0.0000, 0.0000, 1.0000, 0.4000)
1159: ret