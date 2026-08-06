明日方舟 终末地  脸

Shader hash 275d3f82-7a0adecd-7659c1ff-802353cc

vs_5_0
      dcl_globalFlags refactoringAllowed
      dcl_constantbuffer cb0[67], immediateIndexed
      dcl_constantbuffer cb1[27], dynamicIndexed
      dcl_constantbuffer cb2[52], immediateIndexed
      dcl_resource_structured t0, 16
      dcl_input v0.xyz                          
      dcl_input v1.xy
      dcl_input v2.xyz
      dcl_input v3.xyzw
      dcl_input v4.xyz
      dcl_input_sgv v5.x, instanceid
      dcl_input v6.xyzw
      dcl_input v7.xyzw
      dcl_output o0.xy
      dcl_output o1.xyz
      dcl_output o2.xyz
      dcl_output o3.xyzw
      dcl_output o4.xyz
      dcl_output o5.xyz
      dcl_output o6.xyz
      dcl_output o7.xyz
      dcl_output o8.xyz
      dcl_output_siv o9.xyzw, position
      dcl_output o10.x
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


Shader hash ba62322e-7e454938-e7157899-80a5b9ab

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
      dcl_resource_texture2d (float,float,float,float) t1
      dcl_resource_texture2d (float,float,float,float) t2
      dcl_resource_texture3d (float,float,float,float) t3
      dcl_resource_texture3d (float,float,float,float) t4
      dcl_resource_texture3d (float,float,float,float) t5
      dcl_resource_texture2d (float,float,float,float) t6
      dcl_resource_texture2d (float,float,float,float) t7
      dcl_resource_texture2d (float,float,float,float) t8
      dcl_resource_texture2d (float,float,float,float) t9
      dcl_resource_texture2d (float,float,float,float) t10
      dcl_resource_texturecube (float,float,float,float) t11    // 环境贴图cubeMap
      dcl_resource_texture2d (float,float,float,float) t12
      dcl_resource_texture2d (float,float,float,float) t13      // faceControl      
      dcl_resource_texture2d (float,float,float,float) t14
      dcl_resource_texture3d (float,float,float,float) t15
      dcl_input_ps linear v0.xy
      dcl_input_ps linear v1.xyz
      dcl_input_ps linear v2.xyz
      dcl_input_ps linear v3.xyzw
      dcl_input_ps linear v4.xyz
      dcl_input_ps linear v5.xyz
      dcl_input_ps linear v6.xyz
      dcl_input_ps_siv linear noperspective v9.xyw, position
      dcl_input_ps nointerpolation v10.x
      dcl_input_ps_sgv nointerpolation v11.x, isfrontface
      dcl_output o0.xyzw
      dcl_output o1.xyzw
      dcl_temps 33
      dcl_indexableTemp x0[8], 4
   0: sample_b(texture2d)(float,float,float,float) r0.xyzw, v0.xyxx, t10.wxyz, s5, cb0[88].x //SAMPLE_TEXTURECUBE_LOD        baseTex
   1: mul r0.yzw, r0.yyzw, cb5[26].xxyz
   2: mul r1.xyz, r0.wyzw, l(12.9200, 12.9200, 12.9200, 0.0000)
   3: log r2.xyz, abs(r0.wyzw)
   4: mul r2.xyz, r2.xyzx, l(0.4167, 0.4167, 0.4167, 0.0000)
   5: exp r2.xyz, r2.xyzx
   6: mad r2.xyz, r2.xyzx, l(1.0550, 1.0550, 1.0550, 0.0000), l(-0.0550, -0.0550, -0.0550, 0.0000)
   7: ge r3.xyz, l(0.0031, 0.0031, 0.0031, 0.0000), r0.wyzw
   8: movc_sat r1.xyz, r3.xyzx, r1.xyzx, r2.xyzx
   9: mul r2.xw, r1.xxxz, l(31.0000, 0.0000, 0.0000, 0.9688)
  10: round_ni r1.w, r2.x
  11: mad r2.yz, r1.yyzy, l(0.0000, 0.0303, 0.9688, 0.0000), l(0.0000, 0.0005, 0.0156, 0.0000)
  12: mad r2.x, r1.w, l(0.0313), r2.y
  13: sample_l(texture2d)(float,float,float,float) r3.xyz, r2.xzxx, t7.xyzw, s4, l(0)
  14: add r1.yz, r2.xxwx, l(0.0000, 0.0313, 0.0156, 0.0000)
  15: sample_l(texture2d)(float,float,float,float) r2.xyz, r1.yzyy, t7.xyzw, s4, l(0)
  16: mad r1.x, r1.x, l(31.0000), -r1.w
  17: add r1.yzw, -r3.xxyz, r2.xxyz
  18: mad r1.xyz, r1.xxxx, r1.yzwy, r3.xyzx          // 类似colorgrading的lut 结果urp的 ApplyLut2D 按照32的维度计算  gradBaseColor
  19: sample_b(texture2d)(float,float,float,float) r2.xyzw, v0.xyxx, t13.xyzw, s8, cb0[88].x    // faceControl
  20: ishl r1.w, v10.x, l(4)
  21: add r3.xy, v1.xzxx, -cb1[r1.w + 3].xzxx   // 计算世界坐标xz分量与实例位置偏移的差值（v1.xyz为世界坐标）  objectDir
  22: dp3 r3.z, v2.xyzx, v2.xyzx         
  23: rsq r3.w, r3.z
  24: mul r4.xyz, r3.wwww, v2.xyzx          // normalize(normalWS)
  25: dp2 r3.w, r3.xyxx, r3.xyxx
  26: max r3.w, r3.w, l(0.0000)
  27: rsq r3.w, r3.w
  28: mul r5.xz, r3.wwww, r3.xxyx        // normalize(r4.yz)      objectDir
  29: dp3 r3.x, v4.xyzx, v4.xyzx
  30: max r3.x, r3.x, l(0.0000)
  31: rsq r3.x, r3.x
  32: mul r6.xyz, r3.xxxx, v4.xyzx        // normalize(viewDirWS)
  33: mad r3.y, cb5[14].w, l(2.0000), l(-1.0000)     // 双面材质控制反转
  34: movc r3.y, v11.x, l(1.0000), r3.y              // 考虑isfrontface
  35: mul r7.xyz, r3.yyyy, r4.xyzx                         // 反转法线 normalTWS
  36: ftou r8.xy, v9.xyxx                               // screepos
  37: dp3 r9.x, cb0[6].xyzx, cb1[r1.w + 0].xyzx
  38: dp3 r9.y, cb0[6].xyzx, cb1[r1.w + 1].xyzx
  39: dp3 r9.z, cb0[6].xyzx, cb1[r1.w + 2].xyzx     //camVectorOS     相当于把camVector 转到本地空间
  40: dp3 r3.w, r9.xyzx, r9.xyzx
  41: rsq r3.w, r3.w
  42: mul r9.xy, r3.wwww, r9.xzxx              // normalize(camVectorOS)
  43: dp2 r3.w, r9.xyxx, r9.xyxx          // camVectorOS.xz
  44: rsq r3.w, r3.w
  45: mul r4.w, r3.w, r9.y                  // normalize(camVectorOS.z)
  46: add r5.w, -cb0[91].x, l(1.0000)           
  47: mad r5.w, cb0[171].w, r5.w, cb0[91].x   // lerp(cb0[91].x, 1, cb0[171].w)
  48: mul r5.w, r5.w, cb0[89].x                 // lerp(cb0[91].x, 1, cb0[171].w) *  cb0[89].x    // ambeintIntenisty
  49: dp2 r6.w, r7.xzxx, r7.xzxx            //dot(normal.xz, normal.xz)
  50: max r6.w, r6.w, l(0.0000)
  51: rsq r6.w, r6.w
  52: mad r9.xz, r7.xxzx, r6.wwww, -r5.xxzx     
  53: mad r9.xz, r2.yyyy, r9.xxzx, r5.xxzx       // lerp(objectDir, normalize(normal.xz), faceControl.y)     NxzDir
  54: dp2 r6.w, r9.xzxx, r9.xzxx
  55: max r6.w, r6.w, l(0.0000)
  56: rsq r6.w, r6.w
  57: mul r10.xy, r6.wwww, r9.xzxx          //  normalize(NxzDir)
  58: lt r6.w, cb0[161].y, l(0.5000)     // 烘焙光照
  59: if_nz r6.w
{
  60:   add r9.xzw, v1.xxyz, -cb0[175].xxyz
  61:   max r6.w, abs(r9.z), abs(r9.x)
  62:   max r6.w, abs(r9.w), r6.w
  63:   add r7.w, r6.w, l(-896.0000)
  64:   mul_sat r7.w, r7.w, l(0.0156)
  65:   lt r9.x, l(0), cb0[175].w
  66:   lt r9.z, r7.w, l(1.0000)
  67:   and r9.x, r9.z, r9.x
  68:   if_nz r9.x
  69:     add r9.xz, r6.wwww, l(-100.0000, 0.0000, -200.0000, 0.0000)
  70:     mul_sat r9.xz, r9.xxzx, l(0.0833, 0.0000, 0.0625, 0.0000)
  71:     lt r9.xz, r9.xxzx, l(1.0000, 0.0000, 1.0000, 0.0000)
  72:     movc r9.zw, r9.zzzz, l(0.0000, 0.0000, 0.0020, 1.0000), l(0.0000, 0.0000, 0.0005, 2.0000)
  73:     movc r9.xz, r9.xxxx, l(0.0039, 0.0000, 0.0000, 0.0000), r9.zzwz
  74:     mul r11.xyz, r9.xxxx, v1.xyzx
  75:     frc r11.xyz, r11.xyzx
  76:     sample_l(texture3d)(float,float,float,float) r11.xyzw, r11.xyzx, t3.xyzw, s0, r9.z
  77:     mad r11.xyzw, r11.xyzw, l(255.0000, 255.0000, 255.0000, 255.0000), l(0.5000, 0.5000, 0.5000, 0.5000)
  78:     round_ni r11.xyzw, r11.xyzw
  79:     lt r6.w, l(0), r11.w
  80:     if_nz r6.w
  81:       div r9.xzw, v1.xxyz, r11.wwww
  82:       frc r9.xzw, r9.xxzw
  83:       mad r9.xzw, r9.xxzw, l(4.0000, 0.0000, 4.0000, 4.0000), l(0.5000, 0.0000, 0.5000, 0.5000)
  84:       mad r9.xzw, r11.xxyz, l(5.0000, 0.0000, 5.0000, 5.0000), r9.xxzw
  85:       mul r11.xyz, r9.xzwx, cb0[176].xyzx
  86:       sample_l(texture3d)(float,float,float,float) r9.xzw, r11.xyzx, t4.xwyz, s1, l(0)
  87:       mul r11.w, r11.z, l(0.3333)
  88:       sample_l(texture3d)(float,float,float,float) r12.xyz, r11.xywx, t5.xyzw, s1, l(0)
  89:       mad r13.xyz, r11.xyzx, l(1.0000, 1.0000, 0.3333, 0.0000), l(0.0000, 0.0000, 0.3333, 0.0000)
  90:       sample_l(texture3d)(float,float,float,float) r13.xyz, r13.xyzx, t5.xyzw, s1, l(0)
  91:       mad r11.xyz, r11.xyzx, l(1.0000, 1.0000, 0.3333, 0.0000), l(0.0000, 0.0000, 0.6667, 0.0000)
  92:       sample_l(texture3d)(float,float,float,float) r11.xyz, r11.xyzx, t5.xyzw, s1, l(0)
  93:       mad r12.xyz, r12.xyzx, l(4.0000, 4.0000, 4.0000, 0.0000), l(-2.0000, -2.0000, -2.0000, 0.0000)
  94:       mul r12.xyz, r9.xxxx, r12.xyzx
  95:       mad r13.xyz, r13.xyzx, l(4.0000, 4.0000, 4.0000, 0.0000), l(-2.0000, -2.0000, -2.0000, 0.0000)
  96:       mul r13.xyz, r9.zzzz, r13.xyzx
  97:       mad r11.xyz, r11.xyzx, l(4.0000, 4.0000, 4.0000, 0.0000), l(-2.0000, -2.0000, -2.0000, 0.0000)
  98:       mul r11.xyz, r9.wwww, r11.xyzx
  99:       mov r12.w, r9.x
 100:       add r14.xyzw, -r12.xyzw, cb0[178].xyzw
 101:       mad r12.xyzw, r7.wwww, r14.xyzw, r12.xyzw
 102:       mov r13.w, r9.z
 103:       add r14.xyzw, -r13.xyzw, cb0[179].xyzw
 104:       mad r13.xyzw, r7.wwww, r14.xyzw, r13.xyzw
 105:       mov r11.w, r9.w
 106:       add r14.xyzw, -r11.xyzw, cb0[180].xyzw
 107:       mad r11.xyzw, r7.wwww, r14.xyzw, r11.xyzw
 108:     else
 109:       mov r12.xyzw, cb0[178].xyzw
 110:       mov r13.xyzw, cb0[179].xyzw
 111:       mov r11.xyzw, cb0[180].xyzw
 112:     endif
 113:   else
 114:     mov r12.xyzw, cb0[178].xyzw
 115:     mov r13.xyzw, cb0[179].xyzw
 116:     mov r11.xyzw, cb0[180].xyzw
 117:   endif
 118:   mov r10.z, l(1.0000)
 119:   dp3 r14.x, r12.xzwx, r10.xyzx
 120:   dp3 r14.y, r13.xzwx, r10.xyzx
 121:   dp3 r14.z, r11.xzwx, r10.xyzx
 122:   max r9.xzw, r14.xxyz, l(0, 0, 0, 0)
 123:   mul r14.xyw, r5.wwww, r9.zwzx
 124:   mul r15.xyz, r13.xyzx, l(0.7152, 0.7152, 0.7152, 0.0000)
 125:   mad r15.xyz, r12.xyzx, l(0.2126, 0.2126, 0.2126, 0.0000), r15.xyzx
 126:   mad r15.xyz, r11.xyzx, l(0.0722, 0.0722, 0.0722, 0.0000), r15.xyzx
 127:   dp3 r6.w, r15.xyzx, r15.xyzx
 128:   max r6.w, r6.w, l(0.0000)
 129:   rsq r6.w, r6.w
 130:   mul r15.xyz, r6.wwww, r15.xyzx
 131:   mov r15.y, abs(r15.y)
 132:   mov r15.w, l(1.0000)
 133:   dp4 r12.x, r12.xyzw, r15.xyzw
 134:   dp4 r12.y, r13.xyzw, r15.xyzw
 135:   dp4 r12.z, r11.xyzw, r15.xyzw
 136:   max r11.xyz, r12.xyzx, l(0, 0, 0, 0)
 137:   max r6.w, r11.y, r11.x
 138:   max r6.w, r11.z, r6.w
 139:   mul r6.w, r5.w, r6.w
 140:   ge r7.w, r14.x, r14.y
 141:   and r7.w, r7.w, l(1.0000)
 142:   mov r11.xy, r14.yxyy
 143:   mov r11.zw, l(0.0000, 0.0000, -1.0000, 0.6667)
 144:   mad r12.xy, r9.zwzz, r5.wwww, -r11.xyxx
 145:   mov r12.zw, l(0.0000, 0.0000, 1.0000, -1.0000)
 146:   mad r11.xyzw, r7.wwww, r12.xyzw, r11.xyzw
 147:   ge r7.w, r14.w, r11.x
 148:   and r7.w, r7.w, l(1.0000)
 149:   mov r14.xyz, r11.xywx
 150:   mov r11.xyw, r14.wywx
 151:   add r11.xyzw, -r14.xyzw, r11.xyzw
 152:   mad r11.xyzw, r7.wwww, r11.xyzw, r14.xyzw
 153:   min r7.w, r11.y, r11.w
 154:   add r7.w, -r7.w, r11.x
 155:   add r9.x, -r11.y, r11.w
 156:   mad r9.z, r7.w, l(6.0000), l(0.0001)
 157:   div r9.x, r9.x, r9.z
 158:   add r9.x, r9.x, r11.z
 159:   add r9.z, r11.x, l(0.0001)
 160:   div r7.w, r7.w, r9.z
 161:   frc r9.x, abs(r9.x)
 162:   add r12.xyzw, r9.xxxx, l(-0.5000, 1.0000, 0.6667, 0.3333)
 163:   add r9.x, abs(r12.x), l(-0.4500)
 164:   mul_sat r9.x, r9.x, l(-10.0000)
 165:   mad r9.z, r9.x, l(-2.0000), l(3.0000)
 166:   mul r9.x, r9.x, r9.x
 167:   mul r9.x, r9.x, r9.z
 168:   mad r9.x, r9.x, l(-0.3500), l(0.7000)
 169:   mov_sat r11.x, r11.x
 170:   mul r9.x, r9.x, r11.x
 171:   min r7.w, r7.w, r9.x
 172:   add r9.x, -r7.w, l(2.0000)
 173:   rcp r9.x, r9.x
 174:   add r9.x, r9.x, r9.x
 175:   frc r11.xyz, r12.yzwy
 176:   mad r11.xyz, r11.xyzx, l(6.0000, 6.0000, 6.0000, 0.0000), l(-3.0000, -3.0000, -3.0000, 0.0000)
 177:   add_sat r11.xyz, abs(r11.xyzx), l(-1.0000, -1.0000, -1.0000, 0.0000)
 178:   add r11.xyz, r11.xyzx, l(-1.0000, -1.0000, -1.0000, 0.0000)
 179:   mad r11.xyz, r7.wwww, r11.xyzx, l(1.0000, 1.0000, 1.0000, 0.0000)
 180:   mul r9.xzw, r9.xxxx, r11.xxyz   // HSVTORGB end                      shColor
 181:   mov r5.w, r6.w     //SHDominantIntensity            ambeintIntenisty
 182: else
 183:   lt r6.w, l(1.5000), cb0[161].y
 184:   if_nz r6.w
 185:     mul r11.xyz, r7.yyyy, cb0[1].xyzx
 186:     mad r11.xyz, cb0[0].xyzx, r7.xxxx, r11.xyzx
 187:     mad r11.xyz, cb0[2].xyzx, r7.zzzz, r11.xyzx
 188:     dp3 r6.w, r11.xyzx, r11.xyzx
 189:     rsq r6.w, r6.w
 190:     mul r10.zw, r6.wwww, r11.xxxy
 191:     mad r10.zw, r10.zzzw, l(0.0000, 0.0000, 0.5000, 0.5000), l(0.0000, 0.0000, 0.5000, 0.5000)
 192:     sample_b(texture2d)(float,float,float,float) r11.xyw, r10.zwzz, t14.yzwx, s9, cb0[88].x
 193:     ge r6.w, r11.x, r11.y
 194:     and r6.w, r6.w, l(1.0000)
 195:     mov r12.xy, r11.yxyy
 196:     mov r12.zw, l(0.0000, 0.0000, -1.0000, 0.6667)
 197:     add r13.xy, r11.xyxx, -r12.xyxx
 198:     mov r13.zw, l(0.0000, 0.0000, 1.0000, -1.0000)
 199:     mad r12.xyzw, r6.wwww, r13.xyzw, r12.xyzw
 200:     ge r6.w, r11.w, r12.x
 201:     and r6.w, r6.w, l(1.0000)
 202:     mov r11.xyz, r12.xywx
 203:     mov r12.xyw, r11.wywx
 204:     add r12.xyzw, -r11.xyzw, r12.xyzw
 205:     mad r11.xyzw, r6.wwww, r12.xyzw, r11.xyzw
 206:     min r6.w, r11.y, r11.w
 207:     add r6.w, -r6.w, r11.x
 208:     add r7.w, -r11.y, r11.w
 209:     mad r10.z, r6.w, l(6.0000), l(0.0001)
 210:     div r7.w, r7.w, r10.z
 211:     add r7.w, r7.w, r11.z
 212:     add r10.z, r11.x, l(0.0001)
 213:     div r6.w, r6.w, r10.z
 214:     add r10.z, -r6.w, l(2.0000)
 215:     div r10.z, l(2.0000), r10.z
 216:     add r11.xyz, abs(r7.wwww), l(1.0000, 0.6667, 0.3333, 0.0000)
 217:     frc r11.xyz, r11.xyzx
 218:     mad r11.xyz, r11.xyzx, l(6.0000, 6.0000, 6.0000, 0.0000), l(-3.0000, -3.0000, -3.0000, 0.0000)
 219:     add_sat r11.xyz, abs(r11.xyzx), l(-1.0000, -1.0000, -1.0000, 0.0000)
 220:     add r11.xyz, r11.xyzx, l(-1.0000, -1.0000, -1.0000, 0.0000)
 221:     mad r11.xyz, r6.wwww, r11.xyzx, l(1.0000, 1.0000, 1.0000, 0.0000)
 222:     mul r11.xyz, r10.zzzz, r11.xyzx       // rgb hsv 调整完
 223:     add r6.w, -cb0[162].w, l(1.0000)
 224:     mad r9.xzw, r11.xxyz, cb0[162].wwww, r6.wwww // lerp(1, shColor, cb0[162].w)       shColor * cb0[162].w + 1 - cb0[162].w
 225:   else
 226:     mov r9.xzw, cb0[163].xxyz    // shColor
 227:   endif
 228: endif
}
 229: dp2 r6.w, r10.xyxx, cb0[166].xzxx             // ndotsky      normalTWS     NxzDir
 230: add_sat r6.w, r6.w, cb0[167].x
 231: mad r6.w, r6.w, cb0[167].y, cb0[167].z // saturate(ndotsky +  cb0[167].x) * cb0[167].y + cb0[167].z    应用光照强度与偏移：intensity*scale + bias     ndotSky
 232: mad r10.xy, r9.yyyy, r3.wwww, l(0.5000, -0.7500, 0.0000, 0.0000)    //camVectorOS.z *(0.5, -0.75)
 233: mov_sat r10.x, r10.x           // saturate(r10.x)
 234: add r3.w, -r10.x, l(1.0000)   
 235: mad r3.w, r2.y, r3.w, r10.x      // lerp(saturate(r10.x), 1, faceControl.y)
 236: mul r2.x, r2.x, r3.w                  // faceControl.x * lerp(saturate(r10.x), 1, faceControl.y)
 237: dp3_sat r3.w, r7.xyzx, r6.xyzx        // saturate(dot(normalTWS, viewDirWS))    ndotv
 238: mad r3.w, r3.w, l(0.8500), l(0.1500)      // ndotvTWS * 0.85 + 0.15 
 239: add r3.w, -r3.w, l(1.0000)         // 1 - ndotvTWS
 240: mul r2.x, r2.x, cb5[2].z            // (cb5[2].z * (1 - ndotvTWS))
 241: mul_sat r2.x, r2.x, r3.w         // saturate(cb5[2].z * (1 - ndotvTWS) * (1 - ndotvTWS))
 242: add r3.w, -r2.x, l(1.0000)
 243: mad r10.xzw, cb5[24].xxyz, r2.xxxx, r3.wwww    // // lerp(1,  cb5[24].xyz, saturate(cb5[2].z * (1 - ndotvTWS) * (1 - ndotvTWS)))
 244: mul r11.xyz, r0.yzwy, r10.xzwx        // baseColor * lerp(1,  cb5[24].xyz, saturate(cb5[2].z * (1 - ndotvTWS) * (1 - ndotvTWS))) rimTintBaseColor
 245: mul r2.x, r2.y, cb5[0].y                      // cb5[0].y * faceControl.y
 246: add r12.xyz, cb5[19].xyzx, cb1[r1.w + 13].xzyx   //
 247: add r13.xy, -r12.xyxx, cb0[170].ywyy
 248: mad r12.xy, cb0[170].xxxx, r13.xyxx, r12.xyxx   // lerp(cb5[19].xy + cb1[r4.x + 13].xz, cb0[170].yw, cb0[170].x)    //xyControl
 249: add r3.w, -r12.z, l(1.0000)
 250: mad r3.w, cb0[170].x, r3.w, r12.z          // // lerp(r12.z, 1, cb0[170].x)    // 距离差
 251: add r7.w, r12.y, -v1.y                 // r12.y - posiotionWS.y           // 高度差
 252: add r7.w, r7.w, l(0.2000)
 253: mul_sat r7.w, r7.w, l(2.8571)
 254: mad r9.y, r7.w, l(-2.0000), l(3.0000)
 255: mul r7.w, r7.w, r7.w
 256: mul r7.w, r7.w, r9.y
 257: mul r9.y, r3.w, r7.w           ///  r6.w * smoothstep(0, 1, r7.w)  距离差 和高度差的影响
 258: mad r3.w, r7.w, r3.w, r12.x   //  smoothstep(0, 1, r7.w) * r6.w  + r11.x 
 259: lt r3.w, l(0.0001), r3.w
 260: if_nz r3.w           // 是否有下雨的水滴效果
 261:   sqrt r3.z, r3.z        // normalLen
 262:   max r3.z, r3.z, l(0.0000)
 263:   div r3.z, l(1.0000, 1.0000, 1.0000, 1.0000), r3.z   // 计算法线长度的倒数（1/长度）
 264:   lt r3.w, l(0), v3.w                // 检查切线w分量（副切线方向标志）
 265:   movc r3.w, r3.w, l(1.0000), l(-1.0000)
 266:   ge r7.w, cb1[r1.w + 5].w, l(0)
 267:   movc r7.w, r7.w, l(1.0000), l(-1.0000)  // 确定实例级的方向系数（1或-1）
 268:   mul r3.w, r3.w, r7.w                     // 综合切线方向和实例方向的符号
 269:   mul r12.yzw, v2.zzxy, v3.yyzx
 270:   mad r12.yzw, v2.yyzx, v3.zzxy, -r12.yyzw   //// 完成副切线计算：bitangent = cross(normal, tangent)
 271:   mul r12.yzw, r3.wwww, r12.yyzw
 272:   mul r13.xyz, r3.zzzz, v3.xyzx               // tangent
 273:   mul r12.yzw, r3.zzzz, r12.yyzw              // bitangent
 274:   mul r14.xyz, r3.zzzz, v2.xyzx                   // normal
 275:   max r3.z, r9.y, r12.x                  //  max(xyControl.x, r8.w)   //  dotD          距离差 和高度差的影响
 276:   mul r3.w, cb0[82].x, l(0.8000)        // cb0[82].x * 0.8 
 277:   frc r15.y, r3.w                     // frac(cb0[82].x * 0.8 ) 水流速度 
 278:   mov r15.xz, l(0, 0, 0, 0)      
 279:   add r15.xy, r15.xyxx, v0.xyxx               // uv + r15.xy
 280:   sample_b(texture2d)(float,float,float,float) r16.xyzw, r15.xyxx, t8.xyzw, s5, cb0[88].x    // 水流法线    waterdorpControl
 281:   mad r3.w, cb0[82].x, l(0.8000), l(0.0050)      // cb0[82].x * 0.8 + 0.005                 
 282:   frc r15.w, r3.w                // frac(cb0[82].x * 0.8  + 0.005 ) 水流速度1
 283:   add r15.xy, r15.zwzz, v0.xyxx        // 采样uv
 284:   sample_b(texture2d)(float,float,float,float) r15.x, r15.xyxx, t8.wxyz, s5, cb0[88].x   // waterdorpControlW    flowN
 285:   sample_b(texture2d)(float,float,float,float) r3.w, v0.xyxx, t9.xywz, s5, cb0[88].x     // fmask
 286:   mov r15.y, r16.w            // waterdorpControl.w
 287:   mul r15.yz, r3.wwww, r15.xxyx         // r15.xy * frac(cb0[82].x * 0.8  + 0.005 )
 288:   mul r7.w, r3.w, r16.z         // waterdorpControl.z * frac(cb0[82].x * 0.8  + 0.005 )
 289:   mad r16.xy, r16.xyxx, l(2.0000, 2.0000, 0.0000, 0.0000), l(-1.0000, -1.0000, 0.0000, 0.0000)       // flowN * 2 - 1
 290:   add_sat r9.y, r15.z, r15.y          // saturate(r15.z + r15.y)
 291:   mul r11.w, r3.z, r9.y               // saturate(r15.z + r15.y) * dotD
 292:   mul r7.w, r3.z, r7.w                // dotD *  waterdorpControl.z * frac(cb0[82].x * 0.8  + 0.005 )    水流mask
 293:   dp2 r12.x, r16.xyxx, r16.xyxx       // 
 294:   min r12.x, r12.x, l(1.0000)
 295:   add r12.x, -r12.x, l(1.0000)
 296:   sqrt r12.x, r12.x
 297:   max r12.x, r12.x, l(0.0000)           // flowNZ
 298:   mad r13.w, r16.y, l(0.5000), l(0.5000)     //  flowN.y * 0.5 + 0.5
 299:   mul_sat r13.w, r13.w, l(1.2500)            // saturate((flowN.y * 0.5 + 0.5) * 1.25)
 300:   mad r14.w, r13.w, l(-2.0000), l(3.0000)
 301:   mul r13.w, r13.w, r13.w
 302:   mul r15.y, r13.w, r14.w             // smoothstep( saturate((flowN.y * 0.5 + 0.5) * 1.25))        法线y相关
 303:   mad_sat r3.w, r15.x, r3.w, -r15.z         //  saturate uv.x * r3.w - r15.z    // x方向uv*水流 - waterdorpControl.w * 水流
 304:   mad_sat r15.x, r9.y, r3.z, r7.w              //saturate saturate(r15.z + r15.y) * dotD + r7.w  // wetFactor waterdotAff
 305:   mad r13.w, -r14.w, r13.w, l(1.0000)   // 
 306:   mad r3.w, r3.w, r13.w, r15.y          // lerp(r15.y, 1, r3.w)
 307:   add r13.w, -r3.w, l(1.0000)         //
 308:   mad r3.w, r3.w, l(0.8000), r13.w           // (1, 0.8, lerp(r15.y, 1, r3.w))
 309:   add r13.w, -r3.w, l(0.9000)       
 310:   mad r3.w, r2.y, r13.w, r3.w             //lerp(r3.w, 0.9, faceControl.y)    控制相当于边缘固定0.9
 311:   mad r9.y, -r9.y, r3.z, l(1.0000)        // 
 312:   mad r3.w, r3.w, r11.w, r9.y             // lerp(1, r3.w, saturate(r15.z + r15.y) * dotD)  湿润选择
 313:   mul r12.yzw, r12.yyzw, r16.yyyy                
 314:   mad r12.yzw, r16.xxxx, r13.xxyz, r12.yyzw
 315:   mad r12.xyz, r12.xxxx, r14.xyzx, r12.yzwy     // flowN转到世界空间
 316:   dp3 r9.y, r12.xyzx, r12.xyzx
 317:   rsq r9.y, r9.y
 318:   mul r12.xyz, r9.yyyy, r12.xyzx              // normalize(flowNWS)
 319:   mul r12.xyz, r3.yyyy, r12.xyzx          // 考虑isfrontface          // 水点法线
 320:   mad_sat r7.w, r11.w, l(2.0000), r7.w     // saturate(r15.z + r15.y) * dotD * 2 + dotD *  waterdorpControl.z * frac(cb0[82].x * 0.8  + 0.005 )
 321:   mul r3.z, r3.z, r7.w        // dotD *  r7.w   
 322:   mad r7.w, -r2.y, cb5[0].y, l(3.0000)         // 湿润控制 sepcualr f0
 323:   mad r2.x, r3.z, r7.w, r2.x      // lerp(cb5[0].y * faceControl.y, 3, r3.z)          //  类似pbr的f0 specular
 324:   mul r0.x, r0.x, r3.w   // baseTex.w * lerp(1, r3.w, saturate(r15.z + r15.y) * dotD)   丝润控制baseTex.w
 325:   mov r3.z, l(0.3000)               // wet的roungh                 ==> wetRoughness
 326: else
 327:   add r3.z, -cb5[0].x, l(1.0000)   //  wet的roungh                 ==> wetRoughness
 328:   mov r15.x, l(0)            // wetFactor waterdotAff
 329:   mov r12.xyz, r7.xyzx    // / 法线没变
 330: endif
 331: mad r3.w, -cb5[0].z, l(0.9600), l(0.9600)    // // 0.96 - metallic * 0.96
 332: mul r13.xyz, r3.wwww, r11.xyzx    // // (0.96 - metallic * 0.96) * rimTintBaseColor              diffuseColor
 333: mul r2.x, r2.x, l(0.0400)               
 334: mad r0.yzw, r0.yyzw, r10.xxzw, -r2.xxxx       
 335: mad r0.yzw, cb5[0].zzzz, r0.yyzw, r2.xxxx        // lerp(pbrParam.y * 0.04, rimTintBaseColor, metallic)            specularColor
 336: mul r1.xyz, r1.xyzx, r3.wwww              // gradBaseColor * (0.96 - metallic * 0.96)    shadowDiffuseColor
 337: mul r2.x, r3.z, r3.z                      // roughness * roughness         roughnessSqr
 338: max r2.x, r2.x, l(0.0078)                  // max(roughnessSqr, 0.0078)
 339: add r10.xzw, cb0[164].xxyz, cb3[0].xxyz       // 
 340: mad r10.xzw, cb0[161].wwww, r10.xxzw, -cb3[0].xxyz    // lerp(-cb3[0].xyz, cb0[164].xyz, cb0[161].w)         // lightDir
 341: dp2 r7.w, r10.xwxx, r10.xwxx
 342: max r7.w, r7.w, l(0.0000)
 343: rsq r7.w, r7.w
 344: mul r14.xy, r7.wwww, r10.xwxx                 // normalize(r13.xz)        // lightXZ
 345: add r15.yzw, cb0[171].xxyz, -cb3[3].xxyz
 346: mad r15.yzw, cb0[165].wwww, r15.yyzw, cb3[3].xxyz     // lerp(cb3[3].xyzx, cb0[165].xyzx, cb0[165].wwww)   // lightCol
 347: add r7.w, -cb3[3].w, l(1.0000)
 348: mad r7.w, cb0[171].w, r7.w, cb3[3].w
 349: mul r16.xyz, r7.wwww, r15.yzwy                    // lerp(cb3[3].xyzx, cb0[165].xyzx, cb0[165].wwww) * lerp(cb3[3].w, 1, cb0[171].w)    // lightColor
 350: dp3 r9.y, r16.xyzx, l(0.2127, 0.7152, 0.0722, 0.0000) // rIntesity
 351: mov r8.z, l(0)
 352: ld_indexable(texture2d)(float,float,float,float) r14.zw, r8.xyzz, t2.zwxy // screenPos 采样   ShadowTex
 353: ftoi r8.z, cb4[31].x
 354: ilt r8.z, l(0), r8.z
 355: movc r8.z, r8.z, r14.z, cb4[31].z
 356: add r8.z, r8.z, l(-1.0000)
 357: mad r8.z, cb4[30].x, r8.z, l(1.0000)     // lerp(1, shadowTex.x, cb4[30].x)  应用阴影全局强度   sceneShadow
 358: add r11.w, -r8.z, l(1.0000)
 359: mad r8.z, cb0[161].z, r11.w, r8.z      // lerp(sceneShadow, 1,  cb0[161].z)    场景阴影强度    curSceneShadow
 360: dp3 r11.w, r7.xyzx, r10.xzwx          // dot(normalTWS, lightDir)    ndotlt
 361: dp2 r12.w, cb0[6].xzxx, cb0[6].xzxx
 362: rsq r12.w, r12.w
 363: mul r16.xy, r12.wwww, cb0[6].xzxx     // normalize(cb0[6].xz)            // 假定cb0[6] camVector
 364: dp2 r12.w, r14.xyxx, r16.xyxx                              // dot(r16xy, camVector.xy)    camDotLXZ
 365: mul r14.xyz, r1.xyzx, cb0[160].zzzz       // shadowDiffuseColor * cb0[160].z    shadowDiffuseColor             cb0[160].z 暗部强度
 366: mul r16.xyz, r14.xyzx, l(0.6500, 0.6500, 0.6500, 0.0000)  // // shadowDiffuseColor * cb0[160].z * 0.65     satDiff
 367: dp3 r13.w, r16.xyzx, l(0.2127, 0.7152, 0.0722, 0.0000)
 368: mad r16.xyz, r14.xyzx, l(0.6500, 0.6500, 0.6500, 0.0000), -r13.wwww
 369: mad r16.xyz, r16.xyzx, l(1.2000, 1.2000, 1.2000, 0.0000), r13.wwww  // lerp(satDiffIntensity, satDiff, 1.2)   增强饱和度   _2ndShadowDiffuseColor
 370: dp3 r13.w, r13.xyzx, l(0.2127, 0.7152, 0.0722, 0.0000)    // diffIntensity
 371: mad r17.xyz, r11.xyzx, r3.wwww, -r13.wwww
 372: mad r17.xyz, r17.xyzx, l(1.2000, 1.2000, 1.2000, 0.0000), r13.wwww    // lerp(diffInteisty, diffuseColor, 1.2)  增强饱和度  _2ndDiffuseColor
 373: mad r11.w, cb0[164].w, cb0[163].w, r11.w    // mad 偏移cb0[164].w 光照ramp偏移，  cb0[163].w 背光控制 lerp(yFactor * saturate(-camDotLXZ) *(0.5 -0.5 * ndotlt * ndotlt), cb0[164].w, cb0[163])
 374: max r11.w, r11.w, l(-1.0000)
 375: min r11.w, r11.w, l(1.0000)             // // 限制范围
 376: dp3 r18.x, r10.xzwx, cb1[r1.w + 0].xyzx              // dot(LightDIr)
 377: dp3 r18.y, r10.xzwx, cb1[r1.w + 2].xyzx           //lightDir   和 矩阵 x z方向dot
 378: dp2 r13.w, r18.xyxx, r18.xyxx
 379: rsq r13.w, r13.w
 380: mul r18.xz, r13.wwww, r18.xxyx           // 相当于lightDir xz投影normalize    lightPorj
 381: lt r16.w, l(0), r18.x                 // 0 < lightPorj.x
 382: and r16.w, r16.w, l(1.0000)     // 
 383: add r17.w, -v0.x, l(1.0000)       // 1 - uv.x
 384: add r18.x, -r17.w, v0.x          //       
 385: mad r19.x, r16.w, r18.x, r17.w  //   lerp(1 - uv.x, uv.x, 0 < lightPorj.x)
 386: mov r19.y, v0.y                    // uv.y
 387: sample_l(texture2d)(float,float,float,float) r19.xyzw, r19.xyxx, t12.xyzw, s7, l(0)   // 脸部sdf
 388: add r17.w, r19.y, r19.x
 389: mad r18.x, -r19.z, l(2.0000), l(1.0000)
 390: mad r18.w, r19.z, l(2.0000), l(-1.0000)
 391: add r18.w, -r18.x, r18.w
 392: mad r19.x, r16.w, r18.w, r18.x
 393: add r19.y, -abs(r19.x), l(1.0000)
 394: dp2 r16.w, r19.xyxx, r19.xyxx
 395: max r16.w, r16.w, l(0.0000)
 396: rsq r16.w, r16.w
 397: mul r18.xw, r16.wwww, r19.xxxy
 398: mul r19.xyz, r18.wwww, cb1[r1.w + 2].xyzx
 399: mad r19.xyz, cb1[r1.w + 0].xyzx, r18.xxxx, r19.xyzx
 400: dp3 r1.w, r19.xyzx, r19.xyzx
 401: max r1.w, r1.w, l(0.0000)
 402: rsq r1.w, r1.w
 403: mul r19.xyz, r1.wwww, r19.xyzx
 404: mad r4.xyz, r4.xyzx, r3.yyyy, -r19.xyzx
 405: mad r4.xyz, r2.yyyy, r4.xyzx, r19.xyzx
 406: dp3 r1.w, r4.xyzx, r4.xyzx
 407: max r1.w, r1.w, l(0.0000)
 408: rsq r1.w, r1.w
 409: mul r19.xyz, r1.wwww, r4.xyzx
 410: mov_sat r3.y, -r18.z
 411: mad r16.w, r18.z, l(0.5000), l(-1.0000)
 412: mad r16.w, -r18.z, r16.w, l(0.5000)
 413: mov_sat r12.w, -r12.w
 414: mul r3.y, r3.y, r12.w
 415: add r12.w, -cb0[163].w, l(1.0000)
 416: mul r3.y, r3.y, r12.w
 417: mad r12.w, -r18.y, r13.w, r16.w
 418: mad r3.y, r3.y, r12.w, r18.z
 419: mul r12.w, r3.y, l(0.5000)
 420: mad r3.y, -r3.y, l(0.5000), l(0.5000)
 421: max r3.y, r3.y, l(0.0010)
 422: min r3.y, r3.y, l(0.9990)
 423: add r13.w, -r3.y, l(1.0000)
 424: add r13.w, r3.y, -r13.w
 425: max r13.w, r13.w, l(0)
 426: add r3.y, r3.y, r3.y
 427: min r3.y, r3.y, l(1.0000)
 428: add r3.y, -r13.w, r3.y
 429: mad r13.w, -r17.w, l(-0.5000), -r13.w
 430: div r3.y, l(1.0000, 1.0000, 1.0000, 1.0000), r3.y
 431: mul_sat r3.y, r3.y, r13.w
 432: mad r13.w, r3.y, l(-2.0000), l(3.0000)
 433: mul r3.y, r3.y, r3.y
 434: round_pi r16.w, r12.w
 435: mul r12.w, r12.w, r16.w
 436: mad r3.y, -r13.w, r3.y, -r12.w
 437: mad r3.y, abs(r3.y), l(2.0000), l(-1.0000)
 438: add r11.w, -r3.y, r11.w
 439: mad r3.y, r2.y, r11.w, r3.y
 440: mad r18.x, r3.y, l(0.5000), l(0.5000)
 441: mov r18.y, l(0.5000)
 442: sample_l(texture2d)(float,float,float,float) r18.xyzw, r18.xyxx, t6.xyzw, s3, l(0)
 443: max r3.y, r18.y, r18.x
 444: max r3.y, r18.z, r3.y
 445: min r11.w, r18.y, r18.x
 446: min r11.w, r18.z, r11.w
 447: add r3.y, r3.y, -r11.w
 448: mul_sat r10.y, r10.y, l(-2.0000)
 449: mad r11.w, r10.y, l(-2.0000), l(3.0000)
 450: mul r10.y, r10.y, r10.y
 451: mul r10.y, r10.y, r11.w
 452: mul r2.z, r2.z, r10.y
 453: max r2.z, r2.z, r2.y
 454: add r10.y, -r2.z, l(1.0000)
 455: mad r2.z, r14.w, r2.z, r10.y
 456: add r10.y, -r2.y, l(1.0000)
 457: mad r11.w, r2.z, r2.y, r10.y
 458: mad_sat r11.w, r0.x, r11.w, r18.w
 459: mad r20.xyz, r1.xyzx, cb0[160].zzzz, -r16.xyzx
 460: mad r16.xyz, r11.wwww, r20.xyzx, r16.xyzx
 461: min r11.w, r0.x, r2.z
 462: min r11.w, r18.w, r11.w
 463: mul r12.w, r0.x, r2.z
 464: min r13.w, cb0[161].y, l(1.0000)
 465: mul r13.w, r11.w, r13.w
 466: add r20.xyz, -r9.xzwx, l(1.0000, 1.0000, 1.0000, 0.0000)
 467: mad r9.xzw, r13.wwww, r20.xxyz, r9.xxzw
 468: mul r9.xzw, r6.wwww, r9.xxzw
 469: mad r20.xyz, r15.yzwy, r7.wwww, -r9.yyyy
 470: mad r20.xyz, r11.wwww, r20.xyzx, r9.yyyy
 471: max r21.xy, r5.wwww, l(0.0000, 1.2500, 0.0000, 0.0000)
 472: min r21.xy, r21.xyxx, l(1.5000, 1.7500, 0.0000, 0.0000)
 473: mul r21.xzw, r9.xxzw, r21.xxxx
 474: add r6.w, -cb0[165].w, l(1.0000)
 475: mad r15.yzw, r15.yyzw, cb0[165].wwww, r6.wwww
 476: mad r15.yzw, r21.xxzw, r15.yyzw, r20.xxyz
 477: mad r6.w, r5.w, l(0.3500), l(0.6500)
 478: min r6.w, r6.w, l(1.5000)
 479: add r7.w, -r6.w, r21.y
 480: mad r6.w, cb0[161].x, r7.w, r6.w
 481: mul r9.xyz, r9.xzwx, r6.wwww
 482: mul r9.xyz, r9.xyzx, cb0[160].wwww
 483: mad r15.yzw, r15.yyzw, cb0[160].yyyy, -r9.xxyz
 484: mad r9.xyz, r8.zzzz, r15.yzwy, r9.xyzx
 485: mad r15.yzw, r11.xxyz, r3.wwww, -r16.xxyz
 486: mad r15.yzw, r11.wwww, r15.yyzw, r16.xxyz
 487: dp3 r6.w, r15.yzwy, l(0.2127, 0.7152, 0.0722, 0.0000)
 488: add r7.w, -r3.y, l(1.0000)
 489: mad r16.xyz, r18.xyzx, r3.yyyy, r7.wwww
 490: mul r15.yzw, r15.yyzw, r16.xxyz
 491: dp3 r3.y, r15.yzwy, l(0.2127, 0.7152, 0.0722, 0.0000)
 492: max r3.y, r3.y, l(0.0010)
 493: rcp r3.y, r3.y
 494: mul r3.y, r3.y, r6.w
 495: max r3.y, r3.y, l(0)
 496: min r3.y, r3.y, l(1.5000)
 497: mad r16.xyz, -r1.xyzx, cb0[160].zzzz, r17.xyzx
 498: mad r14.xyz, r12.wwww, r16.xyzx, r14.xyzx
 499: mad r15.yzw, r15.yyzw, r3.yyyy, -r14.xxyz
 500: mad r14.xyz, r8.zzzz, r15.yzwy, r14.xyzx
 501: mad r2.z, -r0.x, r2.z, r11.w
 502: mad r2.z, r8.z, r2.z, r12.w
 503: mad r3.y, r2.z, l(0.5000), l(0.5000)
 504: add r6.w, -cb0[160].z, l(1.0000)
 505: mad r2.z, r2.z, r6.w, cb0[160].z
 506: mul r2.z, r2.z, r3.y
 507: mul r15.yzw, r2.zzzz, r9.xxyz
 508: add r2.z, r10.z, l(-0.5000)
 509: mad r16.y, r8.z, r2.z, l(0.5000)
 510: mov r16.xz, cb0[6].xxzx
 511: add r16.xyz, r16.xyzx, r16.xyzx
 512: mad r10.xzw, r10.xxzw, r8.zzzz, r16.xxyz
 513: dp3 r2.z, r10.xzwx, r10.xzwx
 514: max r2.z, r2.z, l(0.0000)
 515: rsq r2.z, r2.z
 516: mad r10.xzw, r10.xxzw, r2.zzzz, r6.xxyz
 517: dp3 r2.z, r10.xzwx, r10.xzwx
 518: max r2.z, r2.z, l(0.0000)
 519: rsq r2.z, r2.z
 520: mul r10.xzw, r2.zzzz, r10.xxzw
 521: dp3_sat r16.x, r12.xyzx, r6.xyzx
 522: dp3 r2.z, r12.xyzx, r10.xzwx
 523: mul r3.y, r2.x, r2.x
 524: mad r6.w, r2.z, r3.y, -r2.z
 525: mad r2.z, r6.w, r2.z, l(1.0000)
 526: mul r2.z, r2.z, r2.z
 527: ne r6.w, r2.z, r3.y
 528: div r2.z, r3.y, r2.z
 529: movc r2.z, r6.w, r2.z, l(1.0000)
 530: mad r3.y, r16.x, l(2.0000), r2.x
 531: add r3.y, r3.y, l(0.0001)
 532: rcp r3.y, r3.y
 533: mul r3.y, r3.y, l(0.5000)
 534: mad r2.z, r2.z, r3.y, l(-0.0001)
 535: max r2.z, r2.z, l(0)
 536: min r2.z, r2.z, l(20.0000)
 537: mul r10.xzw, r0.yyzw, r2.zzzz
 538: lt r2.z, l(0.0010), r15.x
 539: if_nz r2.z
 540:   add r2.z, -r3.z, l(0.0100)
 541:   mad r2.z, r15.x, r2.z, r3.z
 542:   mul r17.y, r2.z, r2.z
 543:   mul r18.x, r16.x, r16.x
 544:   mul r18.z, r16.x, r18.x
 545:   mul r3.y, r17.y, r17.y
 546:   mul r17.z, r17.y, r3.y
 547:   mov r16.yzw, l(0.0000, 0.0365, 9.0632, 0.9904)
 548:   dp2 r20.x, l(3.3271, 1.0000, 0.0000, 0.0000), r16.xyxx
 549:   dp2 r20.y, l(-9.0476, 1.0000, 0.0000, 0.0000), r16.xzxx
 550:   mov r17.x, l(1.0000)
 551:   dp2 r3.y, r20.xyxx, r17.xyxx
 552:   mov r18.yw, l(0.0000, 9.0440, 0.0000, 1.0000)
 553:   dp3 r20.x, l(3.5968, -1.3677, 1.0000, 0.0000), r18.xzwx
 554:   dp3 r20.y, l(-16.3174, 1.0000, 9.2295, 0.0000), r18.xyzx
 555:   mov r21.x, l(5.5659)
 556:   mov r21.yz, r18.xxzx
 557:   dp3 r20.z, l(1.0000, 19.7886, -20.2123, 0.0000), r21.xyzx
 558:   dp3 r6.w, r20.xyzx, r17.xyzx
 559:   div r3.y, r3.y, r6.w
 560:   dp2 r20.x, l(-1.2851, 1.0000, 0.0000, 0.0000), r16.xwxx
 561:   mov r18.x, l(1.2968)
 562:   mov r18.y, r16.x
 563:   dp2 r20.y, l(1.0000, -0.7559, 0.0000, 0.0000), r18.xyxx
 564:   dp2 r6.w, r20.xyxx, r17.xyxx
 565:   dp3 r20.x, l(2.9234, 59.4188, 1.0000, 0.0000), r18.yzwy
 566:   mov r18.xw, l(20.3225, 0.0000, 0.0000, 121.5630)
 567:   dp3 r20.y, l(1.0000, -27.0302, 222.5920, 0.0000), r18.xyzx
 568:   dp3 r20.z, l(626.1300, 316.6270, 1.0000, 0.0000), r18.yzwy
 569:   dp3 r7.w, r20.xyzx, r17.xyzx
 570:   div r6.w, r6.w, r7.w
 571:   mad r16.yzw, r0.yyzw, r3.yyyy, r6.wwww
 572:   add r3.y, r3.y, r6.w
 573:   add r6.w, -r3.y, l(1.0000)
 574:   div r3.y, r6.w, r3.y
 575:   mul r17.xyz, r0.yzwy, r3.yyyy
 576:   mad r16.yzw, r17.xxyz, r16.yyzw, r16.yyzw
 577:   dp3 r3.y, -r6.xyzx, r12.xyzx
 578:   add r3.y, r3.y, r3.y
 579:   mad r17.xyz, r12.xyzx, -r3.yyyy, -r6.xyzx
 580:   max r2.z, r2.z, l(0.0010)
 581:   log r2.z, r2.z
 582:   mad r2.z, -r2.z, l(1.2000), l(1.0000)
 583:   add r2.z, -r2.z, l(6.0000)
 584:   sample_l(texturecube)(float,float,float,float) r17.xyz, r17.xyzx, t11.xyzw, s6, r2.z
 585:   mul r16.yzw, r16.yyzw, r17.xxyz
 586:   max r2.z, r5.w, l(0.5000)
 587:   min r2.z, r2.z, l(1.5000)
 588:   mul r2.z, r2.z, cb0[160].w
 589:   mul r16.yzw, r2.zzzz, r16.yyzw
 590:   mul r16.yzw, r15.xxxx, r16.yyzw
 591: else
 592:   mov r16.yzw, l(0, 0, 0, 0)
 593: endif
 594: mad r10.xzw, r10.xxzw, r15.yyzw, r16.yyzw
 595: mad r9.xyz, r9.xyzx, r14.xyzx, r10.xzwx
 596: dp3 r2.z, r9.xyzx, l(0.2127, 0.7152, 0.0722, 0.0000)
 597: add r3.y, r2.z, l(-0.5000)
 598: max r3.y, r3.y, l(0)
 599: min r3.y, r3.y, l(0.5000)
 600: mad r3.y, r3.y, r3.y, l(1.0000)
 601: add r9.xyz, -r2.zzzz, r9.xyzx
 602: mad r9.xyz, r3.yyyy, r9.xyzx, r2.zzzz
 603: lt r2.z, l(0.0100), cb0[168].w
 604: mul r10.xzw, cb0[6].zzxy, cb0[169].yyzx
 605: mad r10.xzw, cb0[6].yyzx, cb0[169].zzxy, -r10.xxzw
 606: dp3 r3.y, r10.xzwx, r10.xzwx
 607: max r3.y, r3.y, l(0.0000)
 608: rsq r3.y, r3.y
 609: mul r10.xzw, r3.yyyy, r10.xxzw
 610: dp3 r3.y, r6.xyzx, r19.xyzx
 611: add r3.y, -abs(r3.y), l(1.0000)
 612: mad r6.xyz, cb0[167].wwww, l(10.0000, -0.6000, -0.4000, 0.0000), l(-3.0000, 0.8000, 0.9000, 0.0000)
 613: add r5.w, -r6.y, r6.z
 614: add r6.y, r3.y, -r6.y
 615: div r5.w, l(1.0000, 1.0000, 1.0000, 1.0000), r5.w
 616: mul_sat r5.w, r5.w, r6.y
 617: mad r6.y, r5.w, l(-2.0000), l(3.0000)
 618: mul r5.w, r5.w, r5.w
 619: mul r5.w, r5.w, r6.y
 620: add r4.w, abs(r4.w), l(-0.9000)
 621: mul_sat r4.w, r4.w, l(10.0000)
 622: mad r6.y, r4.w, l(-2.0000), l(3.0000)
 623: mul r4.w, r4.w, r4.w
 624: mul r4.w, r4.w, r6.y
 625: dp3 r6.y, cb0[6].xyzx, r10.xzwx
 626: lt r6.y, r6.y, l(-0.0100)
 627: and r6.y, r6.y, l(1.0000)
 628: max r6.y, r4.w, r6.y
 629: mul r5.w, r4.w, r5.w
 630: mov_sat r6.x, r6.x
 631: mad r6.y, r6.y, r2.w, -r5.w
 632: mad r5.w, r6.x, r6.y, r5.w
 633: mul r6.xyz, r5.wwww, cb0[168].xyzx
 634: mul r6.xyz, r6.xyzx, cb0[168].wwww
 635: dp2 r5.w, r5.xzxx, r10.xwxx
 636: add_sat r5.w, r5.w, l(1.0000)
 637: min r0.x, r0.x, r5.w
 638: min r0.x, r14.w, r0.x
 639: mul r6.xyz, r0.xxxx, r6.xyzx
 640: dp3_sat r0.x, r10.xzwx, r19.xyzx
 641: mad r10.xzw, r11.xxyz, r3.wwww, l(-0.2500, 0.0000, -0.2500, -0.2500)
 642: mad r10.xzw, cb0[166].wwww, r10.xxzw, l(0.2500, 0.0000, 0.2500, 0.2500)
 643: mul r10.xzw, r0.xxxx, r10.xxzw
 644: mul r6.xyz, r6.xyzx, r10.xzwx
 645: and r6.xyz, r2.zzzz, r6.xyzx
 646: add r6.xyz, r6.xyzx, r9.xyzx
 647: ushr r9.xy, r8.xyxx, l(5, 5, 0, 0)
 648: imad r0.x, r9.y, cb2[0].w, r9.x
 649: ishl r2.z, r0.x, l(3)
 650: mad r5.w, -cb0[65].y, cb2[2].w, v9.w
 651: ftoi r5.w, r5.w
 652: iadd r6.w, r5.w, -cb2[1].y
 653: iadd r6.w, r6.w, l(1)
 654: imax r6.w, r6.w, l(0)
 655: imin r6.w, r6.w, l(1)
 656: iadd r7.w, cb2[1].y, l(-1)
 657: imin r5.w, r5.w, r7.w
 658: ishl r5.w, r5.w, l(3)
 659: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r9.x, r2.z, l(0), t0.xxxx
 660: bfi r15.xyzw, l(29, 29, 29, 29), l(3, 3, 3, 3), r0.xxxx, l(1, 2, 3, 4)
 661: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r9.y, r15.x, l(0), t0.xxxx
 662: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r9.z, r15.y, l(0), t0.xxxx
 663: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r9.w, r15.z, l(0), t0.xxxx
 664: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r15.x, r15.w, l(0), t0.xxxx
 665: bfi r10.xzw, l(29, 0, 29, 29), l(3, 0, 3, 3), r0.xxxx, l(5, 0, 6, 7)
 666: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r15.y, r10.x, l(0), t0.xxxx
 667: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r15.z, r10.z, l(0), t0.xxxx
 668: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r15.w, r10.w, l(0), t0.xxxx
 669: iadd r0.x, r5.w, cb0[90].y
 670: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r2.z, r0.x, l(0), t0.xxxx
 671: iadd r5.w, -r6.w, l(1)
 672: imul null, r17.x, r2.z, r5.w
 673: iadd r18.xyzw, r0.xxxx, l(1, 2, 3, 4)
 674: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r2.z, r18.x, l(0), t0.xxxx
 675: imul null, r17.y, r5.w, r2.z
 676: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r2.z, r18.y, l(0), t0.xxxx
 677: imul null, r17.z, r5.w, r2.z
 678: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r2.z, r18.z, l(0), t0.xxxx
 679: imul null, r17.w, r5.w, r2.z
 680: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r2.z, r18.w, l(0), t0.xxxx
 681: imul null, r18.x, r5.w, r2.z
 682: iadd r10.xzw, r0.xxxx, l(5, 0, 6, 7)
 683: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r0.x, r10.x, l(0), t0.xxxx
 684: imul null, r18.y, r5.w, r0.x
 685: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r0.x, r10.z, l(0), t0.xxxx
 686: imul null, r18.z, r5.w, r0.x
 687: ld_structured_indexable(structured_buffer, stride=4)(mixed,mixed,mixed,mixed) r0.x, r10.w, l(0), t0.xxxx
 688: imul null, r18.w, r5.w, r0.x
 689: and r9.xyzw, r9.xyzw, r17.xyzw
 690: and r15.xyzw, r15.xyzw, r18.xyzw
 691: mov x0[0].x, r9.x
 692: mov x0[1].x, r9.y
 693: mov x0[2].x, r9.z
 694: mov x0[3].x, r9.w
 695: mov x0[4].x, r15.x
 696: mov x0[5].x, r15.y
 697: mov x0[6].x, r15.z
 698: mov x0[7].x, r15.w
 699: ge r0.x, cb5[0].z, l(0.5000)
 700: add r2.z, -r8.z, l(1.0000)
 701: mad r2.z, r2.z, l(-0.2500), l(0.7500)
 702: mov r5.y, l(0)
 703: mad r4.xyz, r4.xyzx, r1.wwww, -r5.xyzx
 704: mad r4.xyz, r2.yyyy, r4.xyzx, r5.xyzx
 705: dp3 r1.w, r4.xyzx, r4.xyzx
 706: max r1.w, r1.w, l(0.0000)
 707: rsq r1.w, r1.w
 708: mul r4.xyz, r1.wwww, r4.xyzx
 709: mad r1.w, r2.y, l(0.9000), l(0.1000)
 710: div r1.w, l(1.0000, 1.0000, 1.0000, 1.0000), r1.w
 711: mad r9.xyz, r11.xyzx, r3.wwww, l(-0.5000, -0.5000, -0.5000, 0.0000)
 712: and r0.x, r0.x, l(1.0000)
 713: add r2.y, -r2.x, l(0.0100)
 714: mov r11.w, l(1.0000)
 715: mov r15.w, l(1.0000)
 716: mov r10.xzw, r6.xxyz
 717: mov r3.w, l(0)
 718: loop
 719:   ult r5.y, l(7), r3.w
 720:   breakc_nz r5.y
 721:   mov r5.y, x0[r3.w + 0].x
 722:   ishl r5.w, r3.w, l(5)
 723:   mov r16.yzw, r10.xxzw
 724:   mov r6.w, r5.y
 725:   loop
 726:     breakc_z r6.w
 727:     firstbit_lo r7.w, r6.w
 728:     iadd r8.z, r5.w, r7.w
 729:     ishl r7.w, l(1), r7.w
 730:     xor r7.w, r6.w, r7.w
 731:     bfi r17.xyzw, l(29, 29, 29, 29), l(3, 3, 3, 3), r8.zzzz, l(1, 5, 6, 7)
 732:     ftou r9.w, cb3[r17.y + 6].w
 733:     ieq r9.w, r9.w, l(1)
 734:     if_nz r9.w
 735:       ushr r18.xyz, cb3[r17.y + 6].xyzx, l(16, 16, 16, 0)
 736:       f16tof32 r20.xyz, cb3[r17.y + 6].xyzx
 737:       f16tof32 r18.xyz, r18.xzyx
 738:       ushr r21.xyz, cb3[r17.z + 6].xyzx, l(16, 16, 16, 0)
 739:       f16tof32 r22.xyz, cb3[r17.z + 6].xyzx
 740:       f16tof32 r21.xyw, r21.xyxz
 741:       add r11.xyz, v1.xyzx, -cb3[r17.x + 6].xyzx
 742:       mov r23.xz, r20.xxyx
 743:       mov r23.yw, r18.xxxz
 744:       dp4 r9.w, r11.xyzw, r23.xyzw
 745:       mov r18.x, r20.z
 746:       mov r18.z, r22.x
 747:       mov r18.w, r21.x
 748:       dp4 r12.w, r11.xyzw, r18.xyzw
 749:       mov r21.xz, r22.yyzy
 750:       dp4 r11.x, r11.xyzw, r21.xyzw
 751:       max r9.w, abs(r9.w), abs(r12.w)
 752:       max r9.w, abs(r11.x), r9.w
 753:       lt r11.x, l(1.0000), r9.w
 754:       if_nz r11.x
 755:         mov r6.w, r7.w
 756:         continue
 757:       endif
 758:       mad r11.x, cb3[r17.w + 6].x, l(0.5000), l(0.5000)
 759:       add r9.w, r9.w, -r11.x
 760:       add r11.x, -r11.x, l(1.0000)
 761:       div_sat r9.w, r9.w, r11.x
 762:       add r9.w, -r9.w, l(1.0000)
 763:       mul r9.w, r9.w, r9.w
 764:     else
 765:       mov r9.w, l(1.0000)
 766:     endif
 767:     ishl r11.x, r8.z, l(3)
 768:     ftou r11.y, cb3[r11.x + 6].w
 769:     ult r11.z, r11.y, l(2)
 770:     if_nz r11.z
 771:       bfi r11.z, l(29), l(3), r8.z, l(3)
 772:       add r12.w, cb0[169].w, cb3[r11.z + 6].z
 773:       lt r12.w, r12.w, l(0.5000)
 774:       ieq r13.w, l(16), cb3[r11.z + 6].w
 775:       or r12.w, r12.w, r13.w
 776:       if_z r12.w
 777:         bfi r18.xy, l(29, 29, 0, 0), l(3, 3, 0, 0), r8.zzzz, l(2, 4, 0, 0)
 778:         ieq r8.z, l(4), cb3[r11.z + 6].w
 779:         and r11.y, r11.y, l(1)
 780:         ine r12.w, r11.y, l(0)
 781:         lt r13.w, l(0), cb3[r18.x + 6].z
 782:         and r12.w, r12.w, r13.w
 783:         mad r13.w, cb3[r18.x + 6].y, l(0.5000), l(0.5000)
 784:         add r20.z, r13.w, -abs(cb3[r18.x + 6].x)
 785:         add r20.x, -r20.z, cb3[r18.x + 6].y
 786:         add r13.w, -abs(r20.z), l(1.0000)
 787:         add r13.w, -abs(r20.x), r13.w
 788:         max r13.w, r13.w, l(0.0000)
 789:         ge r14.w, cb3[r18.x + 6].x, l(0)
 790:         movc r20.y, r14.w, r13.w, -r13.w
 791:         dp3 r13.w, r20.xyzx, r20.xyzx
 792:         rsq r13.w, r13.w
 793:         mul r20.xyz, r13.wwww, r20.xyzx
 794:         lt r13.w, l(0.5000), cb3[r18.y + 6].z
 795:         and r13.w, r8.z, r13.w
 796:         add r21.xyz, -v1.xyzx, cb3[r17.x + 6].xyzx
 797:         dp3 r14.w, r21.yzxy, -r20.xyzx
 798:         and r13.w, r13.w, l(1.0000)
 799:         movc r13.w, r11.y, l(0), r13.w
 800:         mad r22.xyz, r14.wwww, -r20.zxyz, -r21.xyzx
 801:         mad r21.xyz, r13.wwww, r22.xyzx, r21.xyzx
 802:         dp3 r13.w, r21.xyzx, r21.xyzx
 803:         rsq r14.w, r13.w
 804:         mul r15.xyz, r14.wwww, r21.xyzx
 805:         add r14.w, cb3[r18.y + 6].y, cb3[r18.y + 6].y
 806:         max r14.w, r14.w, l(0.1000)
 807:         movc r14.w, r8.z, r14.w, cb3[r17.z + 6].w
 808:         mul r22.xyz, r20.zxyz, cb3[r18.x + 6].zzzz
 809:         mad r23.xyz, -r22.xyzx, l(0.5000, 0.5000, 0.5000, 0.0000), r21.xyzx
 810:         mad r22.xyz, r22.xyzx, l(0.5000, 0.5000, 0.5000, 0.0000), r21.xyzx
 811:         dp3 r17.y, r23.xyzx, r23.xyzx
 812:         dp3 r17.z, r22.xyzx, r22.xyzx
 813:         sqrt r17.yz, r17.yyzy
 814:         dp3 r18.z, r23.xyzx, r22.xyzx
 815:         mad r18.z, r17.y, r17.z, r18.z
 816:         mad r18.z, r18.z, l(0.5000), l(1.0000)
 817:         rcp r18.z, r18.z
 818:         mul r24.xyz, r15.xyzx, r20.xyzx
 819:         mad r24.xyz, r20.zxyz, r15.yzxy, -r24.xyzx
 820:         dp3 r18.w, r24.xyzx, r24.xyzx
 821:         rsq r18.w, r18.w
 822:         mul r24.xyz, r18.wwww, r24.xyzx
 823:         mul r25.xyz, r20.xyzx, r24.xyzx
 824:         mad r24.xyz, r24.zxyz, r20.yzxy, -r25.xyzx
 825:         dp3 r18.w, r24.xyzx, r24.xyzx
 826:         rsq r18.w, r18.w
 827:         mul r24.xyz, r18.wwww, r24.xyzx
 828:         dp3 r18.w, r24.xyzx, r23.xyzx
 829:         div r17.y, r18.w, r17.y
 830:         dp3 r18.w, r24.xyzx, r22.xyzx
 831:         div r17.z, r18.w, r17.z
 832:         add r17.y, r17.z, r17.y
 833:         mul_sat r17.y, r17.y, l(0.5000)
 834:         mul r24.w, r17.y, r18.z
 835:         movc r22.xyzw, r12.wwww, r24.xyzw, r15.xyzw
 836:         lt r15.x, r14.w, l(0)
 837:         add r15.y, r13.w, l(1.0000)
 838:         div r15.y, l(1.0000, 1.0000, 1.0000, 1.0000), r15.y
 839:         and r12.w, r12.w, l(1.0000)
 840:         add r15.z, -r15.y, r22.w
 841:         mad r12.w, r12.w, r15.z, r15.y
 842:         mul r15.y, cb3[r17.x + 6].w, cb3[r17.x + 6].w
 843:         mul r13.w, r13.w, r15.y
 844:         mad r13.w, -r13.w, r13.w, l(1.0000)
 845:         max r13.w, r13.w, l(0)
 846:         mul r13.w, r13.w, r13.w
 847:         mul r12.w, r12.w, r13.w
 848:         mul r21.xyz, r21.xyzx, cb3[r17.x + 6].wwww
 849:         dp3 r13.w, r21.xyzx, r21.xyzx
 850:         min r13.w, r13.w, l(1.0000)
 851:         add r13.w, -r13.w, l(1.0000)
 852:         log r13.w, r13.w
 853:         mul r13.w, r13.w, r14.w
 854:         exp r13.w, r13.w
 855:         mul r13.w, r13.w, r22.w
 856:         movc r12.w, r15.x, r12.w, r13.w
 857:         dp3 r13.w, r22.yzxy, -r20.xyzx
 858:         add r13.w, r13.w, -cb3[r18.x + 6].z
 859:         mul_sat r13.w, r13.w, cb3[r18.x + 6].w
 860:         mul r13.w, r13.w, r13.w
 861:         mul r13.w, r12.w, r13.w
 862:         movc r12.w, r11.y, r12.w, r13.w
 863:         mul r9.w, r9.w, r12.w
 864:         lt r12.w, l(0), r9.w
 865:         if_nz r12.w
 866:           if_nz r8.z
 867:             dp3 r12.w, r7.xyzx, r22.xyzx
 868:             add_sat r12.w, r12.w, l(0.5000)
 869:             mad r13.w, r12.w, l(-2.0000), l(3.0000)
 870:             mul r12.w, r12.w, r12.w
 871:             mul r12.w, r12.w, r13.w
 872:             add r13.w, l(1.0000), -cb3[r18.y + 6].w
 873:             mad r12.w, r12.w, cb3[r18.y + 6].w, r13.w
 874:             mul r12.w, r12.w, cb3[r18.y + 6].x
 875:             mul r12.w, r9.w, r12.w
 876:             add r15.xyz, -r16.yzwy, cb3[r11.x + 6].xyzx
 877:             mad r16.yzw, r12.wwww, r15.xxyz, r16.yyzw
 878:             mov r15.xyz, r16.yzwy
 879:           else
 880:             mov r15.xyz, r16.yzwy
 881:           endif
 882:           if_z r8.z
 883:             ieq r17.yz, l(0, 1, 3, 0), cb3[r11.z + 6].wwww
 884:             if_z cb3[r11.z + 6].w
 885:               mul r20.xyz, r9.wwww, cb3[r11.x + 6].xyzx
 886:               max r12.w, r20.y, r20.x
 887:               max r12.w, r20.z, r12.w
 888:               mul r12.w, r2.z, r12.w
 889:               max r12.w, r12.w, l(1.0000)
 890:               rcp r12.w, r12.w
 891:               add r13.w, l(1.0000), -cb3[r18.y + 6].y
 892:               mad r12.w, r12.w, cb3[r18.y + 6].y, r13.w
 893:               mul r20.xyz, r12.wwww, cb3[r11.x + 6].xyzx
 894:               mul r12.w, l(0.5000), cb3[r18.y + 6].x
 895:               dp3 r13.w, r4.xyzx, r22.xyzx
 896:               add_sat r13.w, r13.w, l(0.5000)
 897:               mad r14.w, -cb3[r18.y + 6].x, l(0.5000), l(1.0000)
 898:               mad r12.w, r13.w, r14.w, r12.w
 899:               mul r20.xyz, r12.wwww, r20.xyzx
 900:               mov r21.xyz, r14.xyzx
 901:               mov r23.xyz, r14.xyzx
 902:               mov r12.w, l(1.0000)
 903:             else
 904:               ftoi r13.w, cb3[r11.z + 6].x
 905:               add r24.xyz, v1.xyzx, -cb3[r17.x + 6].xyzx
 906:               lt r25.xyz, abs(r24.yzzy), abs(r24.xxyx)
 907:               and r14.w, r25.y, r25.x
 908:               lt r25.xyw, l(0, 0, 0, 0), r24.xyxz
 909:               ushr r17.x, cb3[r18.x + 6].w, l(24)
 910:               ubfe r18.zw, l(0, 0, 8, 8), l(0, 0, 16, 8), cb3[r18.x + 6].wwww
 911:               movc r17.x, r25.x, r17.x, r18.z
 912:               and r18.x, l(255), cb3[r18.x + 6].w
 913:               movc r18.x, r25.y, r18.w, r18.x
 914:               ubfe r18.z, l(8), l(8), cb3[r11.z + 6].x
 915:               and r18.w, l(255), cb3[r11.z + 6].x
 916:               movc r18.z, r25.w, r18.z, r18.w
 917:               movc r18.x, r25.z, r18.x, r18.z
 918:               movc r14.w, r14.w, r17.x, r18.x
 919:               ilt r17.x, r14.w, l(80)
 920:               movc r14.w, r17.x, r14.w, l(-1)
 921:               movc r11.y, r11.y, r14.w, r13.w
 922:               ige r13.w, r11.y, l(0)
 923:               if_nz r13.w
 924:                 dp3 r13.w, r24.xyzx, r24.xyzx
 925:                 max r13.w, r13.w, l(0.0000)
 926:                 rsq r13.w, r13.w
 927:                 mul r18.xzw, r13.wwww, r24.xxyz
 928:                 dp3 r13.w, r7.xyzx, r18.xzwx
 929:                 max r13.w, r13.w, l(0)
 930:                 min r13.w, r13.w, l(0.9000)
 931:                 add r13.w, -r13.w, l(1.0000)
 932:                 mul r24.xy, r13.wwww, cb4[r11.y + 256].xyxx
 933:                 mul r13.w, r24.y, l(5.0000)
 934:                 mad r18.xzw, -r18.xxzw, r24.xxxx, v1.xxyz
 935:                 mad r18.xzw, r7.xxyz, r13.wwww, r18.xxzw
 936:                 ishl r13.w, r11.y, l(2)
 937:                 mul r24.xyzw, r18.zzzz, cb4[r13.w + 33].xyzw
 938:                 mad r24.xyzw, cb4[r13.w + 32].xyzw, r18.xxxx, r24.xyzw
 939:                 mad r24.xyzw, cb4[r13.w + 34].xyzw, r18.wwww, r24.xyzw
 940:                 add r24.xyzw, r24.xyzw, cb4[r13.w + 35].xyzw
 941:                 div r18.xzw, r24.xxyz, r24.wwww
 942:                 add r24.xy, -cb4[r11.y + 312].xyxx, cb4[r11.y + 312].zwzz
 943:                 mad r24.xy, r18.xzxx, r24.xyxx, cb4[r11.y + 312].xyxx
 944:                 ge r25.xyz, l(0, 0, 0, 0), r18.xzwx
 945:                 ge r26.xyz, r18.xzwx, l(1.0000, 1.0000, 1.0000, 0.0000)
 946:                 or r25.xyz, r25.xyzx, r26.xyzx
 947:                 or r13.w, r25.y, r25.x
 948:                 or r13.w, r25.z, r13.w
 949:                 and r14.w, r18.w, l(0x7fffffff)
 950:                 ult r14.w, l(0x7f800000), r14.w
 951:                 or r13.w, r13.w, r14.w
 952:                 mad r18.xz, r24.xxyx, cb4[368].zzwz, l(0.5000, 0.0000, 0.5000, 0.0000)
 953:                 round_ni r18.xz, r18.xxzx
 954:                 mad r24.xy, r24.xyxx, cb4[368].zwzz, -r18.xzxx
 955:                 add r25.xyzw, r24.xxyy, l(0.5000, 1.0000, 0.5000, 1.0000)
 956:                 mul r26.xyzw, r25.xxzz, r25.xxzz
 957:                 mul r24.zw, r26.yyyw, l(0.0000, 0.0000, 0.0800, 0.0800)
 958:                 mad r25.xz, r26.xxzx, l(0.5000, 0.0000, 0.5000, 0.0000), -r24.xxyx
 959:                 add r26.xy, -r24.xyxx, l(1.0000, 1.0000, 0.0000, 0.0000)
 960:                 min r26.zw, r24.xxxy, l(0, 0, 0, 0)
 961:                 mad r26.zw, -r26.zzzw, r26.zzzw, r26.xxxy
 962:                 max r24.xy, r24.xyxx, l(0, 0, 0, 0)
 963:                 mad r24.xy, -r24.xyxx, r24.xyxx, r25.ywyy
 964:                 add r26.zw, r26.zzzw, l(0.0000, 0.0000, 1.0000, 1.0000)
 965:                 add r24.xy, r24.xyxx, l(1.0000, 1.0000, 0.0000, 0.0000)
 966:                 mul r27.xy, r25.xzxx, l(0.1600, 0.1600, 0.0000, 0.0000)
 967:                 mul r28.xy, r26.xyxx, l(0.1600, 0.1600, 0.0000, 0.0000)
 968:                 mul r26.xy, r26.zwzz, l(0.1600, 0.1600, 0.0000, 0.0000)
 969:                 mul r29.xy, r24.xyxx, l(0.1600, 0.1600, 0.0000, 0.0000)
 970:                 mul r24.xy, r25.ywyy, l(0.1600, 0.1600, 0.0000, 0.0000)
 971:                 mov r27.z, r26.x
 972:                 mov r27.w, r24.x
 973:                 mov r28.z, r29.x
 974:                 mov r28.w, r24.z
 975:                 add r25.xyzw, r27.zwxz, r28.zwxz
 976:                 mov r26.z, r27.y
 977:                 mov r26.w, r24.y
 978:                 mov r29.z, r28.y
 979:                 mov r29.w, r24.w
 980:                 add r24.xyz, r26.zywz, r29.zywz
 981:                 div r26.xyz, r28.xzwx, r25.zwyz
 982:                 add r26.xyz, r26.xyzx, l(-2.5000, -0.5000, 1.5000, 0.0000)
 983:                 div r27.xyz, r29.zywz, r24.xyzx
 984:                 add r27.xyz, r27.xyzx, l(-2.5000, -0.5000, 1.5000, 0.0000)
 985:                 mul r26.xyz, r26.yxzy, cb4[368].xxxx
 986:                 mul r27.xyz, r27.xyzx, cb4[368].yyyy
 987:                 mov r26.w, r27.x
 988:                 mad r28.xyzw, r18.xzxz, cb4[368].xyxy, r26.ywxw
 989:                 mad r29.xy, r18.xzxx, cb4[368].xyxx, r26.zwzz
 990:                 mov r27.w, r26.y
 991:                 mov r26.yw, r27.yyyz
 992:                 mad r30.xyzw, r18.xzxz, cb4[368].xyxy, r26.xyzy
 993:                 mad r27.xyzw, r18.xzxz, cb4[368].xyxy, r27.wywz
 994:                 mad r26.xyzw, r18.xzxz, cb4[368].xyxy, r26.xwzw
 995:                 mul r31.xyzw, r24.xxxy, r25.zwyz
 996:                 mul r32.xyzw, r24.yyzz, r25.xyzw
 997:                 mul r14.w, r24.z, r25.y
 998:                 sample_c_lz(texture2d)(float,float,float,float) r17.x, r28.xyxx, t1.xxxx, s2, r18.w
 999:                 sample_c_lz(texture2d)(float,float,float,float) r18.x, r28.zwzz, t1.xxxx, s2, r18.w
1000:                 mul r18.x, r18.x, r31.y
1001:                 mad r17.x, r31.x, r17.x, r18.x
1002:                 sample_c_lz(texture2d)(float,float,float,float) r18.x, r29.xyxx, t1.xxxx, s2, r18.w
1003:                 mad r17.x, r31.z, r18.x, r17.x
1004:                 sample_c_lz(texture2d)(float,float,float,float) r18.x, r27.xyxx, t1.xxxx, s2, r18.w
1005:                 mad r17.x, r31.w, r18.x, r17.x
1006:                 sample_c_lz(texture2d)(float,float,float,float) r18.x, r30.xyxx, t1.xxxx, s2, r18.w
1007:                 mad r17.x, r32.x, r18.x, r17.x
1008:                 sample_c_lz(texture2d)(float,float,float,float) r18.x, r30.zwzz, t1.xxxx, s2, r18.w
1009:                 mad r17.x, r32.y, r18.x, r17.x
1010:                 sample_c_lz(texture2d)(float,float,float,float) r18.x, r27.zwzz, t1.xxxx, s2, r18.w
1011:                 mad r17.x, r32.z, r18.x, r17.x
1012:                 sample_c_lz(texture2d)(float,float,float,float) r18.x, r26.xyxx, t1.xxxx, s2, r18.w
1013:                 mad r17.x, r32.w, r18.x, r17.x
1014:                 sample_c_lz(texture2d)(float,float,float,float) r18.x, r26.zwzz, t1.xxxx, s2, r18.w
1015:                 mad r14.w, r14.w, r18.x, r17.x
1016:                 add r14.w, r14.w, l(-1.0000)
1017:                 mad r11.y, cb4[r11.y + 256].w, r14.w, l(1.0000)
1018:                 movc r12.w, r13.w, l(1.0000), r11.y
1019:               else
1020:                 dp2 r11.y, r5.xzxx, r22.xzxx
1021:                 add_sat r12.w, r11.y, l(1.0000)
1022:               endif
1023:               mov r20.xyz, cb3[r11.x + 6].xyzx
1024:               mov r21.xyz, l(0, 0, 0, 0)
1025:               mov r23.xyz, l(0, 0, 0, 0)
1026:             endif
1027:             dp3 r11.x, r19.xyzx, r22.xyzx
1028:             if_nz r17.y
1029:               add r11.y, r11.x, cb3[r18.y + 6].x
1030:               max r11.y, r11.y, l(-1.0000)
1031:               min r11.y, r11.y, l(1.0000)
1032:               mad r11.y, cb3[r18.y + 6].z, r10.y, r11.y
1033:               mul_sat r11.y, r1.w, r11.y
1034:               mad r13.w, r11.y, l(-2.0000), l(3.0000)
1035:               mul r11.y, r11.y, r11.y
1036:               mul r11.y, r11.y, r13.w
1037:               mul r11.y, r12.w, r11.y
1038:               add r13.w, r19.w, -cb3[r18.y + 6].w
1039:               mul_sat r13.w, r13.w, l(-5.0000)
1040:               mad r14.w, r13.w, l(-2.0000), l(3.0000)
1041:               mul r13.w, r13.w, r13.w
1042:               mul r13.w, r13.w, r14.w
1043:               max r11.x, r11.y, r13.w
1044:               mul r23.xyz, r1.xyzx, cb3[r18.y + 6].yyyy
1045:               mov r21.xyz, r13.xyzx
1046:             else
1047:               mov_sat r11.x, r11.x
1048:             endif
1049:             if_nz r17.z
1050:               mul r18.xzw, r22.zzxy, cb0[6].xxyz
1051:               mad r18.xzw, cb0[6].zzxy, r22.xxyz, -r18.xxzw
1052:               mul r24.xyz, r18.xzwx, cb0[6].zxyz
1053:               mad r18.xzw, cb0[6].yyzx, r18.zzwx, -r24.xxyz
1054:               dp3 r11.y, r18.xzwx, r18.xzwx
1055:               rsq r11.y, r11.y
1056:               mul r18.xzw, r11.yyyy, r18.xxzw
1057:               dp3_sat r11.x, r19.xyzx, -r18.xzwx
1058:               mad r24.xyz, cb3[r18.y + 6].xxxx, l(10.0000, -0.6000, -0.4000, 0.0000), l(-3.0000, 0.8000, 0.9000, 0.0000)
1059:               add r11.y, -r24.y, r24.z
1060:               add r13.w, r3.y, -r24.y
1061:               div r11.y, l(1.0000, 1.0000, 1.0000, 1.0000), r11.y
1062:               mul_sat r11.y, r11.y, r13.w
1063:               mad r13.w, r11.y, l(-2.0000), l(3.0000)
1064:               mul r11.y, r11.y, r11.y
1065:               mul r11.y, r11.y, r13.w
1066:               dp3 r13.w, cb0[6].xyzx, -r18.xzwx
1067:               lt r13.w, r13.w, l(-0.0100)
1068:               and r13.w, r13.w, l(1.0000)
1069:               max r13.w, r4.w, r13.w
1070:               mul r11.y, r4.w, r11.y
1071:               mov_sat r24.x, r24.x
1072:               mad r13.w, r13.w, r2.w, -r11.y
1073:               mad r11.y, r24.x, r13.w, r11.y
1074:               mul r11.y, r12.w, r11.y
1075:               mul r9.w, r9.w, r11.y
1076:               mad r21.xyz, cb3[r18.y + 6].yyyy, r9.xyzx, l(0.5000, 0.5000, 0.5000, 0.0000)
1077:               mov r23.xyz, l(0, 0, 0, 0)
1078:             endif
1079:             if_z r17.z
1080:               ieq r11.y, l(2), cb3[r11.z + 6].w
1081:               add r11.z, l(0.0500), cb3[r18.y + 6].x
1082:               add r11.z, r3.z, -r11.z
1083:               mul_sat r11.z, r11.z, l(-10.0000)
1084:               mad r12.w, r11.z, l(-2.0000), l(3.0000)
1085:               mul r11.z, r11.z, r11.z
1086:               mul r11.z, r11.z, r12.w
1087:               add r12.w, l(1.0000), -cb3[r18.y + 6].z
1088:               mad r12.w, r0.x, cb3[r18.y + 6].z, r12.w
1089:               mul r17.x, r11.z, r12.w
1090:               mov r17.y, cb3[r18.y + 6].y
1091:               movc r11.yz, r11.yyyy, r17.xxyx, l(0.0000, 1.0000, 0.0000, 0.0000)
1092:               mad r11.z, r11.z, r2.y, r2.x
1093:               mad r17.xyz, v4.xyzx, r3.xxxx, r22.xyzx
1094:               dp3 r12.w, r17.xyzx, r17.xyzx
1095:               max r12.w, r12.w, l(0.0000)
1096:               rsq r12.w, r12.w
1097:               mul r17.xyz, r12.wwww, r17.xyzx
1098:               dp3 r12.w, r12.xyzx, r17.xyzx
1099:               mul r13.w, r11.z, r11.z
1100:               mad r14.w, r12.w, r13.w, -r12.w
1101:               mad r12.w, r14.w, r12.w, l(1.0000)
1102:               mul r12.w, r12.w, r12.w
1103:               ne r14.w, r12.w, r13.w
1104:               div r12.w, r13.w, r12.w
1105:               movc r12.w, r14.w, r12.w, l(1.0000)
1106:               mad r11.z, r16.x, l(2.0000), r11.z
1107:               add r11.z, r11.z, l(0.0001)
1108:               rcp r11.z, r11.z
1109:               mul r11.z, r11.z, l(0.5000)
1110:               mad r11.z, r12.w, r11.z, l(-0.0001)
1111:               max r11.z, r11.z, l(0)
1112:               min r11.z, r11.z, l(100.0000)
1113:               mul r17.xyz, r0.yzwy, r11.zzzz
1114:               mul r17.xyz, r11.yyyy, r17.xyzx
1115:               mul r17.xyz, r17.xyzx, cb3[r17.w + 6].zzzz
1116:             else
1117:               mov r17.xyz, l(0, 0, 0, 0)
1118:             endif
1119:             add r18.xyz, r21.xyzx, -r23.xyzx
1120:             mad r18.xyz, r11.xxxx, r18.xyzx, r23.xyzx
1121:             mul r20.xyz, r20.xyzx, r9.wwww
1122:             mul r17.xyz, r17.xyzx, r20.xyzx
1123:             mul r11.xyz, r11.xxxx, r17.xyzx
1124:             mad r11.xyz, r20.xyzx, r18.xyzx, r11.xyzx
1125:             add r16.yzw, r11.xxyz, r16.yyzw
1126:           endif
1127:         else
1128:           mov r15.xyz, r16.yzwy
1129:           mov r8.z, l(0)
1130:         endif
1131:         movc r16.yzw, r8.zzzz, r15.xxyz, r16.yyzw
1132:       endif
1133:     endif
1134:     mov r6.w, r7.w
1135:   endloop
1136:   mov r10.xzw, r16.yyzw
1137:   iadd r3.w, r3.w, l(1)
1138: endloop
1139: div r0.xyz, r10.xzwx, cb0[89].xxxx
1140: lt r0.w, cb0[171].w, l(0.5000)
1141: if_nz r0.w
1142:   eq r0.w, cb0[66].w, l(0)
1143:   add r1.xyz, -v1.xyzx, cb0[32].xyzx
1144:   mov r2.x, cb0[0].z
1145:   mov r2.y, cb0[1].z
1146:   mov r2.z, cb0[2].z
1147:   movc r1.xyz, r0.wwww, r1.xyzx, r2.xyzx
1148:   dp3 r0.w, r1.xyzx, r1.xyzx
1149:   sqrt r1.w, r0.w
1150:   mad r1.w, r1.w, cb0[136].w, -cb0[134].w
1151:   max r1.w, r1.w, l(0)
1152:   add r2.w, -cb0[133].w, cb0[135].w
1153:   mad r3.x, v1.y, l(0.0010), -cb0[133].w
1154:   rsq r0.w, r0.w
1155:   mul r1.xyz, r0.wwww, r1.xyzx
1156:   dp3 r0.w, -r1.xyzx, cb0[136].xyzx
1157:   add r3.yzw, cb0[132].xxyz, cb0[134].xxyz
1158:   add r4.xyz, r3.yzwy, cb0[133].xyzx
1159:   add r2.w, r2.w, -r3.x
1160:   div r2.w, r2.w, cb0[131].w
1161:   max r2.w, r2.w, l(0.0100)
1162:   mul r4.w, r2.w, l(-1.4427)
1163:   exp r4.w, r4.w
1164:   add r4.w, -r4.w, l(1.0000)
1165:   div r2.w, r4.w, r2.w
1166:   div r3.x, -r3.x, cb0[131].w
1167:   mul r3.x, r3.x, l(1.4427)
1168:   exp r3.x, r3.x
1169:   mul r2.w, r2.w, r3.x
1170:   mul r1.w, -r1.w, r2.w
1171:   mul r5.xyz, r4.xyzx, r1.wwww
1172:   mul r5.xyz, r5.xyzx, l(1.4427, 1.4427, 1.4427, 0.0000)
1173:   exp r5.xyz, r5.xyzx
1174:   mad r1.w, r0.w, r0.w, l(1.0000)
1175:   mul r1.w, r1.w, l(0.0597)
1176:   mad r2.w, cb0[132].w, cb0[132].w, l(1.0000)
1177:   add r3.x, cb0[132].w, cb0[132].w
1178:   mad r0.w, -r3.x, r0.w, r2.w
1179:   mad r2.w, -cb0[132].w, cb0[132].w, l(1.0000)
1180:   mul r3.x, r0.w, l(12.5664)
1181:   sqrt r0.w, r0.w
1182:   mul r0.w, r0.w, r3.x
1183:   div r0.w, r2.w, r0.w
1184:   mul r6.xyz, r0.wwww, cb0[132].xyzx
1185:   mad r6.xyz, cb0[134].xyzx, r1.wwww, r6.xyzx
1186:   mul r3.xyz, r3.yzwy, cb0[135].xyzx
1187:   mad r3.xyz, cb0[131].xyzx, r6.xyzx, r3.xyzx
1188:   div r3.xyz, r3.xyzx, r4.xyzx
1189:   max r3.xyz, r3.xyzx, l(0, 0, 0, 0)
1190:   min r3.xyz, r3.xyzx, l(255.0000, 255.0000, 255.0000, 0.0000)
1191:   add r4.xyz, -r5.xyzx, l(1.0000, 1.0000, 1.0000, 0.0000)
1192:   mul r3.xyz, r3.xyzx, r4.xyzx
1193:   mad r3.xyz, r0.xyzx, r5.xyzx, r3.xyzx
1194:   lt r0.w, l(0), cb0[141].z
1195:   if_nz r0.w
1196:     mad r0.w, v9.w, cb0[142].x, cb0[142].y
1197:     log r0.w, r0.w
1198:     mul r0.w, r0.w, cb0[142].z
1199:     div r4.z, r0.w, cb0[141].z
1200:     and r8.w, cb0[88].w, l(7)
1201:     imad r5.xyz, r8.xywx, l(0x0019660d, 0x0019660d, 0x0019660d, 0), l(0.0146, 0.0146, 0.0146, 0.0000)
1202:     imad r0.w, r5.y, r5.z, r5.x
1203:     imad r1.w, r5.z, r0.w, r5.y
1204:     imad r2.w, r0.w, r1.w, r5.z
1205:     imad r5.x, r1.w, r2.w, r0.w
1206:     imad r5.y, r2.w, r5.x, r1.w
1207:     ushr r5.xy, r5.xyxx, l(16, 16, 0, 0)
1208:     utof r5.xy, r5.xyxx
1209:     mad r5.xy, r5.xyxx, l(0.0000, 0.0000, 0.0000, 0.0000), l(-1.0000, -1.0000, 0.0000, 0.0000)
1210:     utof r5.zw, r8.xxxy
1211:     mad r5.xy, cb0[145].wwww, r5.xyxx, r5.zwzz
1212:     mul r4.xy, r5.xyxx, cb0[143].xyxx
1213:     dp3 r0.w, -r1.xyzx, -r2.xyzx
1214:     lt r1.x, l(0.0000), r0.w
1215:     rcp r0.w, r0.w
1216:     and r0.w, r0.w, r1.x
1217:     mul r0.w, r0.w, cb0[141].w
1218:     add r1.xyz, v1.xyzx, -cb0[32].xyzx
1219:     dp3 r1.x, r1.xyzx, r1.xyzx
1220:     max r1.z, r1.x, l(0.0000)
1221:     rsq r1.z, r1.z
1222:     mul r1.w, r1.z, r1.x
1223:     mul r2.x, r0.w, r1.z
1224:     mad r2.y, r2.x, r1.y, cb0[32].y
1225:     mad r1.y, -r2.x, r1.y, r1.y
1226:     mad r0.w, -r0.w, r1.z, l(1.0000)
1227:     mul r0.w, r1.w, r0.w
1228:     add r1.w, r2.y, -cb0[137].x
1229:     mul r1.w, r1.w, cb0[137].z
1230:     max r1.w, r1.w, l(-127.0000)
1231:     exp r1.w, -r1.w
1232:     mul r1.w, r1.w, cb0[137].y
1233:     mul r2.x, r1.y, cb0[137].z
1234:     max r2.x, r2.x, l(-127.0000)
1235:     exp r2.z, -r2.x
1236:     add r2.z, -r2.z, l(1.0000)
1237:     div r2.z, r2.z, r2.x
1238:     mad r2.w, -r2.x, l(0.2402), l(0.6931)
1239:     lt r2.x, l(0.0000), abs(r2.x)
1240:     movc r2.x, r2.x, r2.z, r2.w
1241:     mul r1.w, r1.w, r2.x
1242:     lt r2.x, l(0), cb0[140].y
1243:     add r2.y, r2.y, -cb0[140].z
1244:     mul r2.y, r2.y, cb0[140].x
1245:     max r2.y, r2.y, l(-127.0000)
1246:     exp r2.y, -r2.y
1247:     mul r2.y, r2.y, cb0[140].y
1248:     mul r1.y, r1.y, cb0[140].x
1249:     max r1.y, r1.y, l(-127.0000)
1250:     exp r2.z, -r1.y
1251:     add r2.z, -r2.z, l(1.0000)
1252:     div r2.z, r2.z, r1.y
1253:     mad r2.w, -r1.y, l(0.2402), l(0.6931)
1254:     lt r1.y, l(0.0000), abs(r1.y)
1255:     movc r1.y, r1.y, r2.z, r2.w
1256:     mad r1.y, r2.y, r1.y, r1.w
1257:     movc r1.y, r2.x, r1.y, r1.w
1258:     mul r0.w, r0.w, r1.y
1259:     exp r0.w, -r0.w
1260:     min r0.w, r0.w, l(1.0000)
1261:     max r0.w, r0.w, cb0[139].w
1262:     mad r1.y, -r1.x, r1.z, cb0[138].x
1263:     mad r1.x, r1.x, r1.z, -cb0[138].z
1264:     mul_sat r1.xy, r1.xyxx, cb0[138].wyww
1265:     add r0.w, r0.w, r1.y
1266:     add r0.w, r1.x, r0.w
1267:     min r0.w, r0.w, l(1.0000)
1268:     add r1.x, -r0.w, l(1.0000)
1269:     mul r1.xyz, r1.xxxx, cb0[139].xyzx
1270:     sample_l(texture3d)(float,float,float,float) r2.xyzw, r4.xyzx, t15.xyzw, s1, l(0)
1271:     add r1.w, v9.w, -cb0[144].z
1272:     mul_sat r1.w, r1.w, l(1000000.0000)
1273:     add r2.xyzw, r2.xyzw, l(-0.0000, -0.0000, -0.0000, -1.0000)
1274:     mad r2.xyzw, r1.wwww, r2.xyzw, l(0.0000, 0.0000, 0.0000, 1.0000)
1275:     mad r1.xyz, r1.xyzx, r2.wwww, r2.xyzx
1276:     mul r0.w, r0.w, r2.w
1277:   else
1278:     add r2.xyz, v1.xyzx, -cb0[32].xyzx
1279:     dp3 r1.w, r2.xyzx, r2.xyzx
1280:     max r2.x, r1.w, l(0.0000)
1281:     rsq r2.x, r2.x
1282:     mul r2.z, r1.w, r2.x
1283:     add r2.w, cb0[32].y, -cb0[137].x
1284:     mul r2.w, r2.w, cb0[137].z
1285:     max r2.w, r2.w, l(-127.0000)
1286:     exp r2.w, -r2.w
1287:     mul r2.w, r2.w, cb0[137].y
1288:     mul r3.w, r2.y, cb0[137].z
1289:     max r3.w, r3.w, l(-127.0000)
1290:     exp r4.x, -r3.w
1291:     add r4.x, -r4.x, l(1.0000)
1292:     div r4.x, r4.x, r3.w
1293:     mad r4.y, -r3.w, l(0.2402), l(0.6931)
1294:     lt r3.w, l(0.0000), abs(r3.w)
1295:     movc r3.w, r3.w, r4.x, r4.y
1296:     mul r2.w, r2.w, r3.w
1297:     lt r3.w, l(0), cb0[140].y
1298:     add r4.x, cb0[32].y, -cb0[140].z
1299:     mul r4.x, r4.x, cb0[140].x
1300:     max r4.x, r4.x, l(-127.0000)
1301:     exp r4.x, -r4.x
1302:     mul r4.x, r4.x, cb0[140].y
1303:     mul r2.y, r2.y, cb0[140].x
1304:     max r2.y, r2.y, l(-127.0000)
1305:     exp r4.y, -r2.y
1306:     add r4.y, -r4.y, l(1.0000)
1307:     div r4.y, r4.y, r2.y
1308:     mad r4.z, -r2.y, l(0.2402), l(0.6931)
1309:     lt r2.y, l(0.0000), abs(r2.y)
1310:     movc r2.y, r2.y, r4.y, r4.z
1311:     mad r2.y, r4.x, r2.y, r2.w
1312:     movc r2.y, r3.w, r2.y, r2.w
1313:     mul r2.y, r2.z, r2.y
1314:     exp r2.y, -r2.y
1315:     min r2.y, r2.y, l(1.0000)
1316:     max r2.y, r2.y, cb0[139].w
1317:     mad r2.z, -r1.w, r2.x, cb0[138].x
1318:     mul_sat r2.z, r2.z, cb0[138].y
1319:     mad r1.w, r1.w, r2.x, -cb0[138].z
1320:     mul_sat r1.w, r1.w, cb0[138].w
1321:     add r2.x, r2.z, r2.y
1322:     add r1.w, r1.w, r2.x
1323:     min r0.w, r1.w, l(1.0000)
1324:     add r1.w, -r0.w, l(1.0000)
1325:     mul r1.xyz, r1.wwww, cb0[139].xyzx
1326:   endif
1327:   mad r0.xyz, r3.xyzx, r0.wwww, r1.xyzx
1328: endif
1329: max r0.w, v5.z, l(0.0000)
1330: div r1.xy, v5.xyxx, r0.wwww
1331: max r0.w, v6.z, l(0.0000)
1332: div r1.zw, v6.xxxy, r0.wwww
1333: add r1.xy, -r1.zwzz, r1.xyxx
1334: mul r2.xy, r1.xyxx, l(0.5000, -0.5000, 0.0000, 0.0000)
1335: sqrt r2.xy, abs(r2.xyxx)
1336: mov r1.z, -r1.y
1337: lt r1.yw, l(0, 0, 0, 0), r1.xxxz
1338: lt r1.xz, r1.xxzx, l(0, 0, 0, 0)
1339: iadd r1.xy, -r1.ywyy, r1.xzxx
1340: itof r1.xy, r1.xyxx
1341: mul r1.xy, r1.xyxx, r2.xyxx
1342: mad o1.xy, r1.xyxx, l(0.5000, 0.5000, 0.0000, 0.0000), l(0.5000, 0.5000, 0.0000, 0.0000)
1343: mov o0.xyz, r0.xyzx
1344: mov o0.w, l(1.0000)
1345: mov o1.zw, l(0.0000, 0.0000, 1.0000, 0.4000)
1346: ret