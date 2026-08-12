1 程序化雾noise pass??
2 light tile culling  compute shader 

-----shdow---------
3 cascaded shadow pass(3个级联 1个特殊的shadow)
-4 add soft shadow cast pass
--------------------

-----pre pass mrt------
5 法线深度等的pass(mrt)
------------------------------

----------shadow ao ----
6 四分之一分辨率cascadeshadow 到 screen space (需要3和5的输出深度)
- 7 capsule ao 剔除 compute shader  二分之一分辨率 (需要5输出的法线深度)
- 8 写入线性深度 和 深度buffer  二分之一分辨率 (需要5的输出的深度) (没有capsule ao 启用)
9 ssao pass and blur 二分之一分辨率 (需要8输出的线性深度)
---------------------------------------------

-10 可能需要拷贝的深度(后续效果)  (需要5的输出深度)

----- shadow ao 合并---------------        
--10.5 load 8 的深度buffer(或者用5写入半分辨率深度buffer  有capsule ao 启用)
11 写入二分之一分辨率非过渡区域shadow ao结果buffer(r 级联shadow, a AO) 设置stencil buffer参考值 (需要6的结果和9的结果)
12 写入二分之一分辨率过渡区域shadow ao结果 模板测试 (需要3 5 9)
- 13 写入二分之一分辨率特殊的soft shadow (g通道) (需要3 5)
- 14 写入二分之一分辨率额外的soft shadow (b通道) (需要4 5)
- 15 写入二分之一分辨率capsule ao (a通道) (需要5 7)
        color depth store
------------ screen space subsurface pass------------------------
    load 二分之一分辨率深度buffer 
16 写入皮肤材质的 diffuse only buffer 和 profile   mrt   并用5深度刷新shendubuffer
17       (需要8线性深度,如果没有就用16刷新的深度buffer)
19 Separable SSS 横向 纵向模糊      结果二分之一分辨率

------------render object pass------------------------
20 输入sceneTex depthTex

-----------------depth of field pass------------------------------
21 计算coc radius 获取 scene color ， 输出全分辨率dof buffer(需要20 sceneTex depthTex)
22 TAA pass
23 Depth Of field pass
24 合并结果到scene buffer


-------------transparent pass------------------



#version 460
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 3, binding = 0, std140) uniform _6_8
{
    vec4 _m0[50];
    vec4 _m1;
    uint _m2;
} _8;

layout(set = 0, binding = 0, std140) uniform _49_51
{
    uvec4 _m0;
} _51;

layout(set = 3, binding = 1, rgba32f) uniform writeonly image2D _11;   // 光照index数据


void main()
{
    // 计算了屏幕区域tile的光照索引距离等
    vec2 _62 = vec2(gl_GlobalInvocationID.xy);   // 全局id
    _13 = vec4(_62.x, _62.y, _13.z, _13.w);
    vec2 _76 = (_8._m1.zw * _13.xy) + _8._m1.xy;    // 缩放偏移
    _13 = vec4(_76.x, _76.y, _13.z, _13.w);
    _33 = _13.xy + _8._m1.zw;          //  偏移一个单位
    _46[0u].x = 3.5733110840282835308555104373893e-43;    // _46记录了4个最近的光源index
    _46[1u].x = 3.5733110840282835308555104373893e-43;
    _46[2u].x = 3.5733110840282835308555104373893e-43;
    _46[3u].x = 3.5733110840282835308555104373893e-43;
    _47[0u].x = uintBitsToFloat(0xfffffffcu /* nan */);    // _47存储了4个最近的光源
    _47[1u].x = uintBitsToFloat(0xfffffffdu /* nan */);
    _47[2u].x = uintBitsToFloat(0xfffffffeu /* nan */);
    _47[3u].x = uintBitsToFloat(0xffffffffu /* nan */);
    _16 = _33 + _13.xy;
    _16 *= vec2(0.5);  // 取到像素中心
    _34 = 0u;
    _41 = 0.0;    // index
    while (true)
    {
        _29.x = floatBitsToUint(_41) >= _8._m2;      // 材质支持的最大光照个数
        if (_29.x)           // index >= 2
        {
            break;
        }
        _29 = lessThan(_13.xyxx, _8._m0[floatBitsToInt(_41)].zwzz).xy;
        _29.x = _29.y && _29.x;
        _32 = lessThan(_8._m0[floatBitsToInt(_41)].xyxx, _33.xyxx).xy;
        _29.x = _32.x && _29.x;
        _29.x = _32.y && _29.x;
        if (_29.x)                     // 在范围之内
        {
            _29.x = 3u < _34;      // 判断次数
            if (_29.x)    // 相当于最大存4个范围，其他的用近的替换， 只有最近的4个起作用
            {
                _21.x = _47[3u].x;
                _30.x = _47[2u].x;
                _36 = _47[0u].x;
                _42 = _47[1u].x;
                _38 = max(floatBitsToUint(_42), floatBitsToUint(_36));
                _31 = max(_38, floatBitsToUint(_30.x));
                _26 = max(_31, floatBitsToUint(_21.x));      // 获取最大的距离
                _30 = _8._m0[floatBitsToInt(_41)].zw + _8._m0[floatBitsToInt(_41)].xy;
                _30 = (_30 * vec2(0.5)) + (-_16);   // 范围中心 - 当前位置
                _30.x = dot(_30, _30);
                _30.x *= 1073.7418212890625;
                _31 = uint(_30.x);
                _38 = _31 << 2u;
                _40 = _38 < _26;    // 如果小于这个范围
                if (_40)   // 就替换这个
                {
                    _37 = int(_26 & 3u);
                    _46[_37].x = _41;
                    _21.x = intBitsToFloat(bitfieldInsert(int(_26), int(_31), 2, 30));   // 从第二个bit为插入距离
                    _47[_37].x = _21.x;
                }
                _34 = 4u;
            }
            else        // 记录距离 和 索引
            {
                _46[int(_34)].x = _41;        //记录index
                vec2 _270 = _8._m0[floatBitsToInt(_41)].zw + _8._m0[floatBitsToInt(_41)].xy; //
                _21 = vec4(_270.x, _270.y, _21.z, _21.w);
                vec2 _278 = (_21.xy * vec2(0.5)) + (-_16);   // 范围中心 - 当前位置
                _21 = vec4(_278.x, _278.y, _21.z, _21.w);
                _21.x = dot(_21.xy, _21.xy);
                _21.x *= 1073.7418212890625;
                _26 = uint(_21.x);
                _24 = int(_26) << 2;
                _21.x = intBitsToFloat(int(_34) + _24);   // bit 打包索引到_46和距离
                _47[int(_34)].x = _21.x;
                _34++;
            }
        }
        _41 = intBitsToFloat(floatBitsToInt(_41) + 1);
    }
    _13.x = _46[0u].x;
    _13.x = float(floatBitsToUint(_13.x));
    _13.x *= 0.0039215688593685626983642578125;          // 1 / 255
    _16.x = _46[1u].x;
    _16.x = float(floatBitsToUint(_16.x));
    _13.y = _16.x * 0.0039215688593685626983642578125;
    _16.x = _46[2u].x;
    _16.x = float(floatBitsToUint(_16.x));
    _13.z = _16.x * 0.0039215688593685626983642578125;
    _16.x = _46[3u].x;
    _16.x = float(floatBitsToUint(_16.x));
    _13.w = _16.x * 0.0039215688593685626983642578125;    // 
    bvec3 _373 = equal(ivec4(int(_34)), ivec4(3, 2, 0, 1)).xyw;   // 判断个数
    _20 = bvec4(_373.x, _373.y, _20.z, _373.z);
    _21 = mix(vec4(1.0), _13, bvec4(_34 != 0u));    // 有光照数据
    _13.w = 1.0;
    _21 = mix(_21, _13.xwww, bvec4(_20.w));   // 一个光照
    _21 = mix(_21, _13.xyww, bvec4(_20.y));   // 两个光照
    _13 = mix(_21, _13, bvec4(_20.x));   // 三个光照
    imageStore(_11, ivec2(gl_GlobalInvocationID.xy), _13);   // 光照index数据            没有light的填入了255
}

// 模型数据是一些孤立的点 模拟面片，  然后像素shader 模拟出  球面凸起
layout(location = 0) in vec3 _9;           // localPos
layout(location = 1) in vec2 _11;          // gridPos
layout(location = 2) in vec2 _12;
layout(location = 0) out vec2 _14;          // uv
vec2 _16;
vec2 _17;
vec4 _27;

void main()
{
    _16 = (_11 * vec2(_6._m3, _6._m3)) + _9.xy;   // gridPos * gridSize + localPos       somePos
    _16 *= _6._m0.xy;                               // somePos *  _6._m0.xy            size.zw _6._m0.xy
    _16 = (_16 * vec2(0.5)) + vec2(0.5);    // somePos * 0.5 + 0.5
    _16 = fract(_16);                       // frac(somePos * 0.5 + 0.5)  somePos
    _16 = (_16 * vec2(2.0)) + vec2(-1.0); // somePos * 2 - 1   somePos
    _17 = _12 * vec2(_6._m2, _6._m2);        // uv * _6._m2
    vec2 _85 = (_16 * _6._m0.zw) + _17;     // somePos * _6._m0.zw + uv * _6._m2   //加上粒子大小       size.xy _6._m0.zw
    gl_Position = vec4(_85.x, _85.y, gl_Position.z, gl_Position.w);
    gl_Position = vec4(gl_Position.x, gl_Position.y, vec2(0.0, 1.0).x, vec2(0.0, 1.0).y);
    _14 = _12;        // uv
}

layout(location = 0) in vec2 _10;        // uv
layout(location = 0) out vec4 _12;
float _14;
vec2 _16;
vec3 _19;
float _20;
vec2 _21;
float _22;
float _133;
uint _137;
vec3 _143 = vec3(255.0);

void _32()
{
    _14 = dot(_10, _10);
    _14 = sqrt(_14);
    _21.x = _14 + 9.9999997473787516355514526367188e-06;
    _14 = min(_14, 1.0);
    _14 *= 3.1415927410125732421875;                  // pi * r
    _21 = _10 / _21.xx;           // _21 = normalized_uv = (x/r, y/r)                   //原型范围外的不变   cossin
    _16 = vec2(_14) * _21;     //  pi * r  * uv / (r + e)      // piuv   // scaleUV
    _19.x = sin(_14);            //        sin(pi*r)
    _20 = cos(_14);                // cos(pi*r)
    _14 = ((-_8._m1.y) * _19.x) + _14;   // pi * r - _8._m1.y * sin(pi*r)
    _22 = _20 + 1.0;          // cos(pi*r) + 1               // 编程0 - 2
    _19.z = _22 * _8._m1.x;   // (cos(pi*r) + 1) * _8._m1.x
    vec2 _88 = (_21 * vec2(_14)) + (-_16);   // cossin  * (pi * r - _8._m1.y * sin(pi*r)) - piuv       result           // - cossin * _8._m1.y * sin(pi*r)
    _19 = vec3(_88.x, _88.y, _19.z); //  cossin  * (pi * r - _8._m1.y * sin(pi*r)) - piuv , (cos(pi*r) + 1) * _8._m1.x   // 感觉像是模拟一个平面上半球凸起
    vec3 _95 = _19 * vec3(15.91549396514892578125, 15.91549396514892578125, 50.0);   // result * (15.9, 15.9, 50)
    _12 = vec4(_95.x, _95.y, _95.z, _12.w);
    _12.w = 1.0;
}

layout(set = 2, binding = 0) uniform sampler2D _18;  // 

layout(location = 0) in vec2 _20;     // uv
layout(location = 0) out vec4 _22;

vec3 _525 = vec3(255.0);

void _53()
{
    vec2 _64 = (-_14._m17.xy) + _14._m17.zw;
    _24 = vec3(_64.x, _64.y, _24.z);
    vec2 _74 = (_20 * _24.xy) + _14._m17.xy;
    _24 = vec3(_74.x, _74.y, _24.z);        // lerp(_14._m17.xy, _14._m17.zw, uv)  range   范围   
    _39 = _24.xy * vec2(_14._m55.x, _14._m55.y);    // range * _14._m55.xy
    _26 = (_39.xyxy * _14._m4.xxyy) + _14._m6;
    _28 = (_39.xyxy * _14._m4.zzww) + _14._m7;     // 4种缩放偏移
    _31 = textureLod(_18, _26.xy, 0.0).xyz;
    vec2 _122 = _31.xy * _14._m8.xx;
    _32 = vec3(_122.x, _122.y, _32.z);
    _32.z = _31.z * _14._m9.x;
    _27 = textureLod(_18, _26.zw, 0.0).xyz;
    vec2 _143 = _27.xy * _14._m8.yy;
    _30 = vec3(_143.x, _143.y, _30.z);
    _30.z = _27.z * _14._m9.y;
    vec3 _155 = _30 * vec3(0.00999999977648258209228515625);
    _26 = vec4(_155.x, _155.y, _155.z, _26.w);
    _31 = textureLod(_18, _28.xy, 0.0).xyz;
    vec2 _168 = _31.xy * _14._m8.zz;
    _33 = vec3(_168.x, _168.y, _33.z);
    _33.z = _31.z * _14._m9.z;
    _29 = textureLod(_18, _28.zw, 0.0).xyz;
    vec2 _187 = _29.xy * _14._m8.ww;
    _30 = vec3(_187.x, _187.y, _30.z);
    _30.z = _29.z * _14._m9.w;                        // 4次采样 xy 和 z 分别缩放
    vec3 _201 = (_32 * vec3(0.00999999977648258209228515625)) + _26.xyz;
    _26 = vec4(_201.x, _201.y, _201.z, _26.w);
    vec3 _208 = (_33 * vec3(0.00999999977648258209228515625)) + _26.xyz;
    _26 = vec4(_208.x, _208.y, _208.z, _26.w);
    vec3 _215 = (_30 * vec3(0.00999999977648258209228515625)) + _26.xyz;       // 采样相加 * 0.01
    _26 = vec4(_215.x, _215.y, _215.z, _26.w);     // 结果
    _43 = 0.5 < _14._m60;   //是否启用
    if (_43)
    {
        _40 = dot(_14._m41.xy, _39);     // rangeL
        _28.x = dot(_14._m41.zw, _39);
        _37 = dot(_14._m42.xy, _39);
        _39.x = dot(_14._m42.zw, _39);        // 计算四个基础值
        vec2 _263 = ((-_24.xy) * vec2(_14._m55.x, _14._m55.y)) + _8._m6.xy;
        _24 = vec3(_263.x, _263.y, _24.z);        // -range * _14._m55.xy + _8._m6.xy;
        _24.x = dot(_24.xy, _24.xy);
        _24.x = sqrt(_24.x);       //  len
        _24.x += (-_14._m57);      
        _35 = (-_14._m57) + _14._m63;
        _35 += 0.00999999977648258209228515625;
        _24.x /= _35;               
        _24.x = clamp(_24.x, 0.0, 1.0); // saturate((len - _14._m57) / (_14._m63 - 14._m57))   distF
        _24.x = (-_24.x) + 1.0;      // 1 - distF
        _35 = _14._m43.x + _14._m44.x;
        _36 = (-_35) + _14._m43.x;
        _24.x = (_24.x * _36) + _35;         // lerp(_14._m43.x + _14._m44.x, _14._m43.x, 1 - distF)
        _36 = (_40 * 0.4000000059604644775390625) + (-_14._m0.x);       // rangeL * 0.4 -_14._m0.x
        _30.x = sin(_36);
        _32.x = cos(_36);
        _36 = _30.x * _14._m45.x;
        _30.z = _24.x * _32.x;                   // ripple1.z = cos(angle1) * falloff;
        vec2 _358 = vec2(_36) * _14._m41.xy;        //  ripple1.xy = sin(angle1) * _14._m45.x * _14._m41.xy;   特定方向的叠加
        _30 = vec3(_358.x, _358.y, _30.z);        
        _36 = (_28.x * 0.20000000298023223876953125) + (-_14._m0.y);
        _28.x = sin(_36);
        _32.x = cos(_36);
        _36 = _28.x * _14._m45.y;
        _32.z = _24.x * _32.x;
        vec2 _391 = vec2(_36) * _14._m41.zw;
        _32 = vec3(_391.x, _391.y, _32.z);
        vec3 _396 = _30 + _32;
        _28 = vec4(_396.x, _28.y, _396.y, _396.z);
        _36 = (_37 * 0.20000000298023223876953125) + (-_14._m0.y);
        _30.x = sin(_36);
        _32.x = cos(_36);
        _36 = _30.x * _14._m45.y;
        _30.z = _24.x * _32.x;
        vec2 _427 = vec2(_36) * _14._m42.xy;
        _30 = vec3(_427.x, _427.y, _30.z);
        vec3 _433 = _28.xzw + _30;
        _28 = vec4(_433.x, _433.y, _433.z, _28.w);
        _36 = (_39.x * 0.60000002384185791015625) + (-_14._m0.x);
        _30.x = sin(_36);
        _32.x = cos(_36);
        _36 = _30.x * _14._m45.w;
        _30.z = _24.x * _32.x;
        vec2 _466 = vec2(_36) * _14._m42.zw;
        _30 = vec3(_466.x, _466.y, _30.z);
        _24 = _28.xyz + _30;         // 将四层波纹叠加起来    
        vec3 _476 = _24 + _26.xyz;              //  将动态细节与之前的基础噪声形态相结合
        _26 = vec4(_476.x, _476.y, _476.z, _26.w);
    }
    _22 = vec4(_26.xzy.x, _26.xzy.y, _26.xzy.z, _22.w);      //  结果 不执行if 就是采样了4次的结果
    _22.w = 0.0;
}



// normal motionvector pass
#version 460

invariant gl_Position;

layout(location = 0) in vec4 _19;   // positionOS
layout(location = 1) in vec3 _21;   // normalOS
layout(location = 2) in vec3 _22;   // oldPositionOS
layout(location = 0) out vec4 _25;  // nonjitterPositionCS
layout(location = 1) out vec4 _26;  // previousPositionCSNoJitter
layout(location = 2) out vec3 _28;  // normalWS


void main()
{
    vec3 _64 = _19.yyy * _12._m0[1u].xyz;
    _30 = vec4(_64.x, _64.y, _64.z, _30.w);
    vec3 _75 = (_12._m0[0u].xyz * _19.xxx) + _30.xyz;
    _30 = vec4(_75.x, _75.y, _75.z, _30.w);
    vec3 _87 = (_12._m0[2u].xyz * _19.zzz) + _30.xyz;
    _30 = vec4(_87.x, _87.y, _87.z, _30.w);
    vec3 _96 = _30.xyz + _12._m0[3u].xyz;
    _30 = vec4(_96.x, _96.y, _96.z, _30.w);      // positionWS
    vec3 _106 = _30.xyz + (-_6._m5);            // 偏移?
    _30 = vec4(_106.x, _106.y, _106.z, _30.w);
    _34 = _30.yyyy * _17._m1[1u];
    _34 = (_17._m1[0u] * _30.xxxx) + _34;
    _34 = (_17._m1[2u] * _30.zzzz) + _34;
    _34 += _17._m1[3u];
    _24 = _34;
    gl_Position = _34;                        // positionCS
    _34 = _30.yyyy * _17._m2[1u];
    _34 = (_17._m2[0u] * _30.xxxx) + _34;    // _NonJitteredViewProjMatrix
    _30 = (_17._m2[2u] * _30.zzzz) + _34;
    _25 = _30 + _17._m2[3u];                // nonjitterPositionCS
    _33 = 0.0 < _12._m14.x; 
    vec3 _170 = mix(_19.xyz, _22, bvec3(_33));    // 选择os pos
    _30 = vec4(_170.x, _170.y, _170.z, _30.w);
    vec3 _179 = _30.yyy * _12._m12[1u].xyz;
    _34 = vec4(_179.x, _179.y, _179.z, _34.w);
    vec3 _190 = (_12._m12[0u].xyz * _30.xxx) + _34.xyz;
    _30 = vec4(_190.x, _190.y, _30.z, _190.z);
    vec3 _201 = (_12._m12[2u].xyz * _30.zzz) + _30.xyw;
    _30 = vec4(_201.x, _201.y, _201.z, _30.w);
    vec3 _209 = _30.xyz + _12._m12[3u].xyz;
    _30 = vec4(_209.x, _209.y, _209.z, _30.w);       // oldPositionWS
    vec3 _217 = _30.xyz + (-_6._m5);                
    _30 = vec4(_217.x, _217.y, _217.z, _30.w);
    _34 = _30.yyyy * _17._m0[1u];
    _34 = (_17._m0[0u] * _30.xxxx) + _34;
    _30 = (_17._m0[2u] * _30.zzzz) + _34;
    _26 = _30 + _17._m0[3u];                  // previousPositionCSNoJitter
    _36.x = dot(_21, _12._m1[0u].xyz);
    _36.y = dot(_21, _12._m1[1u].xyz);
    _36.z = dot(_21, _12._m1[2u].xyz);
    _38 = dot(_36, _36);
    _38 = inversesqrt(_38);
    _36 = vec3(_38) * _36;
    _28 = _36;                  // normalWS
}

#version 460

layout(constant_id = 4) const uint _2 = 0u;

struct _37
{
    float _m0;
    float _m1;
    float _m2;
    float _m3;
};

const float _191[4] = float[](-0.01171875, 0.00390625, 0.01171875, -0.00390625);

layout(set = 0, binding = 0, std140) uniform _38_40
{
    vec4 _m0;
    uint _m1;
    uint _m2;
    int _m3;
    int _m4;
    ivec4 _m5;
    uvec4 _m6;
    _37 _m7;
} _40;


layout(location = 0) in vec4 _6;   // nonjitterPositionCS
layout(location = 1) in vec4 _7;   // previousPositionCSNoJitter
layout(location = 2) in vec3 _10;  // normalWS
layout(location = 0) out vec4 _12;   // motion vector  xy高8为， zw 低8位
layout(location = 1) out vec4 _13; // 压缩的normalWS
vec4 _15;
uvec4 _18;
vec4 _19;
int _22;
vec2 _25;
vec2 _26;
ivec2 _29;
float _31;
int _32;
bool _35;
float _210;
uint _214;
vec3 _221 = vec3(255.0);
uint _261;
vec3 _263 = vec3(255.0);

void _43()
{
    vec2 _49 = _6.xy / _6.ww;                       // 
    _15 = vec4(_49.x, _49.y, _15.z, _15.w);         // screenPos
    _26 = _7.xy / _7.ww;                     // oldScreePos
    vec2 _61 = (-_26) + _15.xy;
    _15 = vec4(_61.x, _61.y, _15.z, _15.w);          // 
    vec2 _71 = (_15.xy * vec2(0.2495000064373016357421875)) + vec2(0.49999237060546875);   // 把 [-2,2] 范围缩放映射到 [0,1] 区间
    _15 = vec4(_71.x, _71.y, _15.z, _15.w);
    vec2 _78 = _15.xy * vec2(65535.0);      // 映射到 16-bit 整数范围
    _15 = vec4(_78.x, _78.y, _15.z, _15.w);
    uvec2 _84 = uvec2(_15.xy);
    _18 = uvec4(_84.x, _84.y, _18.z, _18.w);
    _29 = ivec2(_18.xy & uvec2(4294967040u));      // & 0xFFFFFF00 = 保留高位字节，低 8 bit 清零
    uvec2 _98 = (-uvec2(_29)) + _18.xy;    
    _18 = uvec4(_18.x, _18.y, _98.x, _98.y);   // 相当于取出低 8 bit 到_98
    uvec2 _105 = _18.xy >> uvec2(8u);   // 提取高8位
    _18 = uvec4(_105.x, _105.y, _18.z, _18.w);
    _19 = vec4(_18.xzyw);
    _15 = _19 * vec4(0.0039215688593685626983642578125);  // 1 / 255          除以 255 -> [0,1] 范围归一化
    _12 = _15;                                      // motion vector??
    _15.x = dot(_10, _10);                           //
    _15.x = inversesqrt(_15.x);
    vec3 _129 = _15.xxx * _10;
    _15 = vec4(_129.x, _129.y, _129.z, _15.w);          // normalWS
    _32 = int((0.0 < _15.z) ? 4294967295u : 0u);
    _22 = int((_15.z < 0.0) ? 4294967295u : 0u);
    _32 = (-_32) + _22;
    _31 = float(_32);
    _35 = _31 < 0.0;
    _13.z = _35 ? 0.49500000476837158203125 : 0.50499999523162841796875;  // z 通道存一个接近 0.5 的值，略微偏移用来区分正反面 float zChannel = (facingFlag < 0.0) ? 0.495 : 0.505;
    _25.x = abs(_15.z) + 1.0;        // // stereographic projection球面映射（）编码 // 把 xy 压缩到 [-1, 1] 区间内，并用 z 做修正
    _25 = _15.xy / _25.xx;
    vec2 _174 = (_25 * vec2(0.5)) + vec2(0.5);
    _13 = vec4(_174.x, _174.y, _13.z, _13.w);      // // 压缩到 [0,1] 以便存进贴图
    _13.w = 0.0;
}

void main()
{
    vec3 _217 = vec3(0.0);
    vec3 _262 = vec3(0.0);
    _43();
    if (_2 != 0u)
    {
        _210 = _191[((uint(gl_FragCoord.x) & 1u) << 1u) | (uint(gl_FragCoord.y) & 1u)];
        _214 = (_2 >> 0u) & 3u;   // 2×2 Bayer dither pattern    有序抖动量化 (ordered dithering)
        switch (_214)
        {
            case 1u:
            {
                _217 = vec3(_210 * 2.0);      // // 抖动强度
                _221 = vec3(15.0);            // 4bit 量化 (0..15)
                break;
            }
            case 2u:
            {
                _217 = vec3(_210);
                _221 = vec3(31.0);         // 5bit 量化 (0..31)
                break;
            }
            case 3u:
            {
                _217 = vec3(_210, _210 * 0.5, _210);
                _221 = vec3(31.0, 63.0, 31.0);        // R=5bit, G=6bit, B=5bit
                break;
            }
        }
        vec3 _247 = _12.xyz + _217;
        _12 = vec4(_247.x, _247.y, _247.z, _12.w);
        vec3 _256 = round(_12.xyz * _221) / _221;
        _12 = vec4(_256.x, _256.y, _256.z, _12.w);  //从而模拟 低精度颜色格式（比如 444、555、565）而不产生生硬的 banding
        _261 = (_2 >> 2u) & 3u;
        switch (_261)
        {
            case 1u:
            {
                _262 = vec3(_210 * 2.0);
                _263 = vec3(15.0);
                break;
            }
            case 2u:
            {
                _262 = vec3(_210);
                _263 = vec3(31.0);
                break;
            }
            case 3u:
            {
                _262 = vec3(_210, _210 * 0.5, _210);
                _263 = vec3(31.0, 63.0, 31.0);
                break;
            }
        }
        vec3 _282 = _13.xyz + _262;
        _13 = vec4(_282.x, _282.y, _282.z, _13.w);
        vec3 _291 = round(_13.xyz * _263) / _263;
        _13 = vec4(_291.x, _291.y, _291.z, _13.w);
    }
}


//depth only 
#version 460

struct _41
{
    float _m0;
    float _m1;
    float _m2;
    float _m3;
};

layout(set = 3, binding = 0, std140) uniform _4_6
{
    vec4 _m0;
    vec4 _m1;
    vec4 _m2;
    vec4 _m3;
    vec4 _m4;
    vec3 _m5;
    vec3 _m6;
    vec3 _m7;
    vec4 _m8;
    vec4 _m9;
    vec4 _m10;
    vec4 _m11;
    vec3 _m12;
    float _m13;
    vec4 _m14;
    vec4 _m15;
    vec4 _m16;
} _6;

layout(set = 3, binding = 1, std140) uniform _10_12
{
    vec4 _m0[4];
    vec4 _m1[4];
    vec4 _m2;
    vec4 _m3;
    vec4 _m4;
    vec3 _m5;
    vec3 _m6;
    vec4 _m7;
    vec4 _m8;
    vec4 _m9;
    vec4 _m10;
    vec4 _m11;
    vec4 _m12[4];
    vec4 _m13[4];
    vec4 _m14;
} _12;

layout(set = 3, binding = 2, std140) uniform _15_17
{
    vec4 _m0[4];
    vec4 _m1[4];
    vec4 _m2[4];
    vec4 _m3[4];
    vec4 _m4[4];
    vec4 _m5[4];
    vec4 _m6[4];
    vec4 _m7[4];
    vec4 _m8;
    vec4 _m9;
    vec4 _m10;
    vec4 _m11[6];
} _17;

layout(set = 1, binding = 0, std140) uniform _35_37
{
    vec4 _m0;
    vec3 _m1;
} _37;

layout(set = 0, binding = 0, std140) uniform _42_44
{
    vec4 _m0;
    uint _m1;
    uint _m2;
    int _m3;
    int _m4;
    ivec4 _m5;
    uvec4 _m6;
    _41 _m7;
} _44;

layout(location = 0) in vec4 _19;       // positionOS
layout(location = 1) in vec3 _21;       // normalOS
layout(location = 2) in vec2 _24;       // uv
vec2 _26;
vec4 _28;
vec4 _29;
vec3 _31;
vec3 _32;
float _34;
vec4 _46;

void main()
{
    _26 = _24;
    _28.x = _12._m0[0u].x;
    _28.y = _12._m0[1u].x;
    _28.z = _12._m0[2u].x;
    _31.x = dot(_28.xyz, _21);
    _28.x = _12._m0[0u].y;
    _28.y = _12._m0[1u].y;
    _28.z = _12._m0[2u].y;
    _31.y = dot(_28.xyz, _21);
    _28.x = _12._m0[0u].z;
    _28.y = _12._m0[1u].z;
    _28.z = _12._m0[2u].z;
    _31.z = dot(_28.xyz, _21);
    _34 = dot(_31, _31);
    _34 = inversesqrt(_34);
    _31 = vec3(_34) * _31;          // normalWS
    _34 = dot(_37._m1, _31);        //    ndotl
    _34 = clamp(_34, 0.0, 1.0);
    _34 = (-_34) + 1.0;         // 1 - ndotl
    _28.x = _34 * _37._m0.y;   // float scale = invNdotL * _ShadowBias.y;
    _32 = _19.yyy * _12._m0[1u].xyz;     
    _32 = (_12._m0[0u].xyz * _19.xxx) + _32;
    _32 = (_12._m0[2u].xyz * _19.zzz) + _32;
    _32 += _12._m0[3u].xyz;                        // positionWS
    vec3 _164 = (_31 * _28.xxx) + _32;                  
    _28 = vec4(_164.x, _164.y, _164.z, _28.w);  // normalWS * scale.xxx + positionWS
    vec3 _173 = _28.xyz + (-_6._m5);         //  偏移
    _28 = vec4(_173.x, _173.y, _173.z, _28.w);
    _29 = _28.yyyy * _17._m1[1u];
    _29 = (_17._m1[0u] * _28.xxxx) + _29;
    _28 = (_17._m1[2u] * _28.zzzz) + _29;
    _28 += _17._m1[3u];                         // positionCS
    gl_Position.z = _28.z + _37._m0.x;          // positionCS.z + _ShadowBias.x
    gl_Position = vec4(_28.xyw.x, _28.xyw.y, gl_Position.z, _28.xyw.z);      // positionCS
}
像素shader 返回 0

#version 460
invariant gl_Position;

struct _43
{
    float _m0;
    float _m1;
    float _m2;
    float _m3;
};

layout(set = 3, binding = 0, std140) uniform _4_6
{
    vec4 _m0;
    vec4 _m1;
    vec4 _m2;
    vec4 _m3;
    vec4 _m4;
    vec3 _m5;
    vec3 _m6;
    vec3 _m7;
    vec4 _m8;
    vec4 _m9;
    vec4 _m10;
    vec4 _m11;
    vec3 _m12;
    float _m13;
    vec4 _m14;
    vec4 _m15;
    vec4 _m16;
} _6;

layout(set = 3, binding = 1, std140) uniform _10_12
{
    vec4 _m0[4];
    vec4 _m1[4];
    vec4 _m2;
    vec4 _m3;
    vec4 _m4;
    vec3 _m5;
    vec3 _m6;
    vec4 _m7;
    vec4 _m8;
    vec4 _m9;
    vec4 _m10;
    vec4 _m11;
    vec4 _m12[4];
    vec4 _m13[4];
    vec4 _m14;
} _12;

layout(set = 3, binding = 2, std140) uniform _15_17
{
    vec4 _m0[4];
    vec4 _m1[4];
    vec4 _m2[4];
    vec4 _m3[4];
    vec4 _m4[4];
    vec4 _m5[4];
    vec4 _m6[4];
    vec4 _m7[4];
    vec4 _m8;
    vec4 _m9;
    vec4 _m10;
    vec4 _m11[6];
} _17;

layout(set = 1, binding = 0, std140) uniform _37_39
{
    vec4 _m0;
    vec3 _m1;
} _39;

layout(set = 0, binding = 0, std140) uniform _44_46
{
    vec4 _m0;
    uint _m1;
    uint _m2;
    int _m3;
    int _m4;
    ivec4 _m5;
    uvec4 _m6;
    _43 _m7;
} _46;

layout(location = 0) in vec4 _19;
layout(location = 1) in vec3 _21;
layout(location = 2) in vec2 _24;      // uv
layout(location = 0) out vec4 _26;      // positionCS
layout(location = 1) out vec2 _28;    // uv
vec4 _30;
vec4 _31;
vec3 _33;
vec3 _34;
float _36;
vec4 _47;

void main()
{
    _30.x = _12._m0[0u].x;
    _30.y = _12._m0[1u].x;
    _30.z = _12._m0[2u].x;
    _33.x = dot(_30.xyz, _21);
    _30.x = _12._m0[0u].y;
    _30.y = _12._m0[1u].y;
    _30.z = _12._m0[2u].y;
    _33.y = dot(_30.xyz, _21);
    _30.x = _12._m0[0u].z;
    _30.y = _12._m0[1u].z;
    _30.z = _12._m0[2u].z;
    _33.z = dot(_30.xyz, _21);
    _36 = dot(_33, _33);
    _36 = inversesqrt(_36);
    _33 = vec3(_36) * _33;
    _36 = dot(_39._m1, _33);
    _36 = clamp(_36, 0.0, 1.0);
    _36 = (-_36) + 1.0;
    _30.x = _36 * _39._m0.y;
    _34 = _19.yyy * _12._m0[1u].xyz;
    _34 = (_12._m0[0u].xyz * _19.xxx) + _34;
    _34 = (_12._m0[2u].xyz * _19.zzz) + _34;
    _34 += _12._m0[3u].xyz;
    vec3 _164 = (_33 * _30.xxx) + _34;
    _30 = vec4(_164.x, _164.y, _164.z, _30.w);
    vec3 _173 = _30.xyz + (-_6._m5);
    _30 = vec4(_173.x, _173.y, _173.z, _30.w);
    _31 = _30.yyyy * _17._m1[1u];
    _31 = (_17._m1[0u] * _30.xxxx) + _31;
    _30 = (_17._m1[2u] * _30.zzzz) + _31;
    _30 += _17._m1[3u];
    _30.z += _39._m0.x;
    gl_Position = _30;
    _26 = _30;      
    _28 = _24;
}

#version 460

layout(constant_id = 4) const uint _2 = 0u;

struct _55
{
    float _m0;
    float _m1;
    float _m2;
    float _m3;
};

const float _251[4] = float[](-0.01171875, 0.00390625, 0.01171875, -0.00390625);

layout(set = 3, binding = 3, std140) uniform _11_13
{
    vec4 _m0[4];
    vec4 _m1;
    vec4 _m2;
    vec4 _m3;
    vec4 _m4;
    float _m5;
    float _m6;
    float _m7;
} _13;

layout(set = 3, binding = 0, std140) uniform _15_17
{
    vec4 _m0;
    vec4 _m1;
    vec4 _m2;
    vec4 _m3;
    vec4 _m4;
    vec3 _m5;
    vec3 _m6;
    vec3 _m7;
    vec4 _m8;
    vec4 _m9;
    vec4 _m10;
    vec4 _m11;
    vec3 _m12;
    float _m13;
    vec4 _m14;
    vec4 _m15;
    vec4 _m16;
} _17;

layout(set = 3, binding = 4, std140) uniform _19_21
{
    vec4 _m0[4];
    vec4 _m1;
    vec4 _m2;
    vec4 _m3;
    vec4 _m4;
    vec4 _m5;
    vec4 _m6;
    vec4 _m7;
    vec4 _m8;
    vec4 _m9;
    vec4 _m10;
    vec4 _m11;
    vec4 _m12;
    int _m13;
    float _m14;
    float _m15;
    float _m16;
    float _m17;
    float _m18;
    float _m19;
    float _m20;
    float _m21;
    float _m22;
    float _m23;
    float _m24;
    float _m25;
    float _m26;
    float _m27;
    float _m28;
    float _m29;
    float _m30;
    float _m31;
    float _m32;
    float _m33;
    float _m34;
    vec3 _m35;
    float _m36;
    float _m37;
    float _m38;
    float _m39;
    float _m40;
    float _m41;
    float _m42;
    float _m43;
    float _m44;
    float _m45;
    float _m46;
    float _m47;
} _21;

layout(set = 0, binding = 0, std140) uniform _56_58
{
    vec4 _m0;
    uint _m1;
    uint _m2;
    int _m3;
    int _m4;
    ivec4 _m5;
    uvec4 _m6;
    _55 _m7;
} _58;

layout(set = 2, binding = 0) uniform sampler2D _25;

layout(location = 0) in vec4 _27;           // positionCS
layout(location = 1) in vec2 _30;           // uv
layout(location = 0) out vec4 _32;
vec4 _8[16];
vec4 _34;
vec4 _35;
vec4 _36;
bvec4 _40;
vec2 _42;
float _44;
ivec2 _47;
bool _49;
float _50;
int _52;
float _269;
uint _273;
vec3 _280 = vec3(255.0);

void _61()
{
    // https://digitalrune.github.io/DigitalRune-Documentation/html/fa431d48-b457-4c70-a590-d44b0840ab1e.htm
    _8[0u] = vec4(0.0588235296308994293212890625, 0.0, 0.0, 0.0);
    _8[1u] = vec4(0.529411792755126953125, 0.0, 0.0, 0.0);
    _8[2u] = vec4(0.17647059261798858642578125, 0.0, 0.0, 0.0);
    _8[3u] = vec4(0.64705884456634521484375, 0.0, 0.0, 0.0);
    _8[4u] = vec4(0.7647058963775634765625, 0.0, 0.0, 0.0);
    _8[5u] = vec4(0.2941176593303680419921875, 0.0, 0.0, 0.0);
    _8[6u] = vec4(0.88235294818878173828125, 0.0, 0.0, 0.0);
    _8[7u] = vec4(0.4117647111415863037109375, 0.0, 0.0, 0.0);
    _8[8u] = vec4(0.23529411852359771728515625, 0.0, 0.0, 0.0);
    _8[9u] = vec4(0.705882370471954345703125, 0.0, 0.0, 0.0);
    _8[10u] = vec4(0.117647059261798858642578125, 0.0, 0.0, 0.0);
    _8[11u] = vec4(0.588235318660736083984375, 0.0, 0.0, 0.0);
    _8[12u] = vec4(0.941176474094390869140625, 0.0, 0.0, 0.0);
    _8[13u] = vec4(0.4705882370471954345703125, 0.0, 0.0, 0.0);
    _8[14u] = vec4(0.823529422283172607421875, 0.0, 0.0, 0.0);
    _8[15u] = vec4(0.3529411852359771728515625, 0.0, 0.0, 0.0);   // Screen-Door Transparency
    _34 = vec4(_27.xx.x, _34.y, _27.xx.y, _34.w);
    vec2 _137 = _27.yy * _17._m8.xx;     // y的缩放
    _34 = vec4(_34.x, _137.x, _34.z, _137.y);        // 对应屏幕uv xyxy
    _34 /= _27.wwww;                         // screenuv
    _34 = (_34 * vec4(0.5)) + vec4(0.5);
    _35 = _34 * vec4(1024.0, 1024.0, 4096.0, 4096.0);  // 缩放1024 或者4096
    _40 = greaterThanEqual(_35.zzww, -_35.zzww);
    _36.x = _40.x ? 4.0 : (-4.0);
    _36.y = _40.y ? 0.25 : (-0.25);
    _36.z = _40.z ? 4.0 : (-4.0);
    _36.w = _40.w ? 0.25 : (-0.25);
    _42 = _35.xy * _36.yw;      // 先缩小
    _42 = fract(_42);           // fract
    _42 = _36.xz * _42;       // 放大
    _47 = ivec2(_42);      //        相当于对 xy % 4
    _52 = _47.y << 2;  // 
    _47.x = _52 + _47.x; //  相当于 y * 4 + x   索引
    _50 = texture(_25, _30, _13._m7).w;  // alpha
    _42.x = _50 * _21._m4.w;
    _42.x = clamp(_42.x, 0.0, 1.0);   // alpha
    _44 = _42.x + (-_8[_47.x].x);
    _44 += (-_21._m43);
    _49 = _44 < 0.0;
    if (_49)            // 透明剔除
    {
        discard;
    }
    _32 = vec4(0.0);
}

void _62()
{
    _8[0u] = vec4(0.0588235296308994293212890625, 0.0, 0.0, 0.0);
    _8[1u] = vec4(0.529411792755126953125, 0.0, 0.0, 0.0);
    _8[2u] = vec4(0.17647059261798858642578125, 0.0, 0.0, 0.0);
    _8[3u] = vec4(0.64705884456634521484375, 0.0, 0.0, 0.0);
    _8[4u] = vec4(0.7647058963775634765625, 0.0, 0.0, 0.0);
    _8[5u] = vec4(0.2941176593303680419921875, 0.0, 0.0, 0.0);
    _8[6u] = vec4(0.88235294818878173828125, 0.0, 0.0, 0.0);
    _8[7u] = vec4(0.4117647111415863037109375, 0.0, 0.0, 0.0);
    _8[8u] = vec4(0.23529411852359771728515625, 0.0, 0.0, 0.0);
    _8[9u] = vec4(0.705882370471954345703125, 0.0, 0.0, 0.0);
    _8[10u] = vec4(0.117647059261798858642578125, 0.0, 0.0, 0.0);
    _8[11u] = vec4(0.588235318660736083984375, 0.0, 0.0, 0.0);
    _8[12u] = vec4(0.941176474094390869140625, 0.0, 0.0, 0.0);
    _8[13u] = vec4(0.4705882370471954345703125, 0.0, 0.0, 0.0);
    _8[14u] = vec4(0.823529422283172607421875, 0.0, 0.0, 0.0);
    _8[15u] = vec4(0.3529411852359771728515625, 0.0, 0.0, 0.0);
    _35.x = texture(_25, _30, _13._m7).w;     // alpha
    _40 = _35.x * _21._m4.w;
    _40 = clamp(_40, 0.0, 1.0);
    _51.x = _40 + (-_21._m14);  // alpha
    _38 = _51.x < 0.0;
    if (_38)
    {
        discard;
    }
    _34 = vec4(_27.xx.x, _34.y, _27.xx.y, _34.w);
    vec2 _167 = _27.yy * _17._m8.xx;
    _34 = vec4(_34.x, _167.x, _34.z, _167.y);
    _34 /= _27.wwww;
    _34 = (_34 * vec4(0.5)) + vec4(0.5);
    _35 = _34 * vec4(1024.0, 1024.0, 4096.0, 4096.0);
    _44 = greaterThanEqual(_35.zzww, -_35.zzww);
    _41.x = _44.x ? 4.0 : (-4.0);
    _41.y = _44.y ? 0.25 : (-0.25);
    _41.z = _44.z ? 4.0 : (-4.0);
    _41.w = _44.w ? 0.25 : (-0.25);
    _51 = _35.xy * _41.yw;
    _51 = fract(_51);
    _51 *= _41.xz;
    _48 = ivec2(_51);
    _53 = _48.y << 2;
    _48.x = _53 + _48.x;
    _45 = _40 + (-_8[_48.x].x);
    _45 += (-_21._m43);
    _49 = _45 < 0.0;
    if (_49)
    {
        discard;
    }
    _32 = vec4(0.0);
}

void _34()
{
    _21 = texture(_14, _16.xy).w;
    _20 = (_21 * _10._m6.w) + (-_10._m19);
    _24 = _20 < 0.0;
    if (_24)
    {
        discard;
    }
    _18 = vec4(0.0);
}

//计算阴影pass screen space   第一次 pcf把cascade shadow 放到四分之一分辨率的贴图上
#version 460

layout(constant_id = 4) const uint _2 = 0u;

struct _90
{
    float _m0;
    float _m1;
    float _m2;
    float _m3;
};

const float _1056[4] = float[](-0.01171875, 0.00390625, 0.01171875, -0.00390625);

layout(set = 3, binding = 0, std140) uniform _10_12
{
    vec4 _m0;
    vec4 _m1;
    vec4 _m2;
    vec4 _m3;
    vec4 _m4;
    vec3 _m5;
    vec3 _m6;
    vec3 _m7;
    vec4 _m8;
    vec4 _m9;
    vec4 _m10;
    vec4 _m11;
    vec3 _m12;
    float _m13;
    vec4 _m14;
    vec4 _m15;
    vec4 _m16;
} _12;

layout(set = 3, binding = 2, std140) uniform _16_18
{
    vec4 _m0[4];
    vec4 _m1[4];
    vec4 _m2[4];
    vec4 _m3[4];
    vec4 _m4[4];
    vec4 _m5[4];
    vec4 _m6[4];
    vec4 _m7[4];
    vec4 _m8;
    vec4 _m9;
    vec4 _m10;
    vec4 _m11[6];
} _18;

layout(set = 3, binding = 3, std140) uniform _21_23
{
    vec4 _m0[12];
    vec4 _m1;
    vec4 _m2[4];
} _23;

layout(set = 3, binding = 4, std140) uniform _32_34
{
    vec4 _m0[20];
    vec4 _m1[20];
    vec4 _m2[16];
    float _m3[16];
    vec4 _m4;
    vec4 _m5;
    vec4 _m6;
    vec4 _m7;
    vec4 _m8;
    vec4 _m9;
    vec4 _m10;
    float _m11[4];
    vec4 _m12;
    vec4 _m13;
    vec4 _m14;
    vec4 _m15;
    vec4 _m16;
    vec4 _m17;
    float _m18;
    float _m19;
    float _m20;
    vec4 _m21[5];
} _34;

layout(set = 3, binding = 1, std140) uniform _36_38
{
    vec2 _m0;
    float _m1;
    vec4 _m2;
} _38;

layout(set = 0, binding = 0, std140) uniform _91_93
{
    vec4 _m0;
    uint _m1;
    uint _m2;
    int _m3;
    int _m4;
    ivec4 _m5;
    uvec4 _m6;
    _90 _m7;
} _93;

layout(set = 2, binding = 0) uniform sampler2D _42;
layout(set = 2, binding = 1) uniform sampler2D _43;

layout(location = 0) in vec2 _45;    // uv
layout(location = 0) out float _47;
vec4 _8[4];
vec4 _49;
ivec2 _53;
uint _55;
bool _58;
vec3 _60;
vec4 _61;
vec4 _62;
bvec4 _65;
vec4 _66;
float _68;
bvec4 _69;
vec4 _70;
ivec2 _71;
bvec4 _72;
vec4 _73;
bvec4 _74;
vec3 _75;
bvec3 _78;
vec3 _79;
float _80;
ivec2 _81;
vec2 _83;
float _84;
float _85;
bool _86;
float _87;
float _1074;
uint _1077;
vec3 _1081 = vec3(255.0);

void _96()
{
    _8[0u] = vec4(1.0, 0.0, 0.0, 0.0);
    _8[1u] = vec4(0.0, 1.0, 0.0, 0.0);
    _8[2u] = vec4(0.0, 0.0, 1.0, 0.0);
    _8[3u] = vec4(0.0, 0.0, 0.0, 1.0);
    vec2 _120 = (_38._m2.xy * vec2(0.300000011920928955078125)) + _45; // float2 sampleUV = CameraDepthTexture_TexelSize.xy * 0.300000012 + uv.xy;
    _49 = vec4(_120.x, _120.y, _49.z, _49.w);
    _49.x = texture(_43, _49.xy).x;  // float  depth    = SAMPLE_TEXTURE2D_X(_CustomDepthTexture, sampler_PointClamp, sampleUV).r;
    _49.x = (_49.x * 2.0) + (-1.0);  // 转换深度值到NDC空间（DirectX -> GL，[0,1]->[-1,1]） depth = depth * 2.0 - 1.0;
    _49 = (_49.xxxx * _18._m5[2u]) + _18._m5[3u]; // （Z轴贡献）float4 worldPos = depth.xxxx * invViewProjMatrix[2].xyzw + invViewProjMatrix[3].xyzw;
    _60.y = _45.y * _12._m8.x; // float2  clipPos1.xy = float2(vs_TEXCOORD0.x, vs_TEXCOORD0.y * ProjectionParams.x);
    _60.x = _45.x;
    _61.x = -1.0;
    _61.y = -_12._m8.x;   // float2 clipPos2.xy = float2(-1.0, -ProjectionParams.x);
    vec2 _167 = (_60.xy * vec2(2.0)) + _61.xy;       // clipPos1.xy = clipPos1.xy * 2.0 + clipPos2.xy;
    _60 = vec3(_167.x, _167.y, _60.z);    // clipPos1
    _49 = (_60.yyyy * _18._m5[1u]) + _49;
    _49 = (_60.xxxx * _18._m5[0u]) + _49;   // worldPos
    _85 = 1.0 / _49.w;         // 6. 透视除法 float InvworldPos = 1.0 / (worldPos.w);
    _60 = vec3(_85) * _49.xyz;   // worldPos       scaledDir
    vec3 _200 = (_49.xyz * vec3(_85)) + _12._m5; 
    _49 = vec4(_200.x, _200.y, _200.z, _49.w); //float4 offsetPos = float4(worldPos.xyz * InvworldPos + WorldSpaceCameraPos.xyz, 0.0);
    vec2 _208 = _60.yy * _23._m2[1u].xy;
    _61 = vec4(_208.x, _208.y, _61.z, _61.w);
    vec2 _219 = (_23._m2[0u].xy * _60.xx) + _61.xy;
    _61 = vec4(_219.x, _219.y, _61.z, _61.w);
    vec2 _230 = (_23._m2[2u].xy * _60.zz) + _61.xy;
    _61 = vec4(_230.x, _230.y, _61.z, _61.w);
    vec2 _238 = _61.xy + _23._m2[3u].xy;
    _61 = vec4(_238.x, _238.y, _61.z, _61.w);         // 
    vec2 _245 = (_61.xy * vec2(2.0)) + vec2(-1.0);     // float4 shadowUV = mul(transpose(CloseUpWorldToShadow), float4(scaledDir.xyz, 1.0));
    _61 = vec4(_245.x, _245.y, _61.z, _61.w);              //            shadowUV.xy  = shadowUV.xy * 2.0 - 1.0;
    bvec2 _256 = lessThan(abs(_61.xyxx), vec4(0.9900000095367431640625, 0.9900000095367431640625, 0.0, 0.0)).xy; //isUVValid.xy     = (abs(shadowUV.xyxx) < float4(0.99000001, 0.99000001, 0.0, 0.0)).xy;
    _65 = bvec4(_256.x, _256.y, _65.z, _65.w); // 检查UV是否在有效范围内（避免边缘采样）
    _86 = _65.y && _65.x;   
    _62.x = float(_86);          // 是否在特殊的一个灯光内             
    _68 = (-_62.x) + 1.0;    //  bool  isFullyValid     = isUVValid.y && isUVValid.x;
    vec3 _277 = _49.xyz + (-_34._m6.xyz);            //10. 计算到各级联球体中心的向量
    _70 = vec4(_277.x, _277.y, _277.z, _70.w);
    _70.z = dot(_70.xyz, _70.xyz);
    vec3 _292 = _49.xyz + (-_34._m4.xyz);
    _73 = vec4(_292.x, _292.y, _292.z, _73.w);
    _70.x = dot(_73.xyz, _73.xyz);
    vec3 _307 = _49.xyz + (-_34._m5.xyz);
    _73 = vec4(_307.x, _307.y, _307.z, _73.w);
    vec3 _315 = _49.xyz + (-_12._m6);            
    _49 = vec4(_315.x, _315.y, _315.z, _49.w); //   toCameraVec         offsetPos.xyz - WorldSpaceCameraPos;
    _79.x = dot(_49.xyz, _49.xyz);    // distanceSq = dot(toCameraVec.xyz, toCameraVec.xyz);
    _58 = _79.x >= _34._m9.w;
    _49.x = float(_58);               // distanceSq > _34._m9.w
    _70.y = dot(_73.xyz, _73.xyz);            // 计算到各级联球体中心的向量
    _78 = lessThan(_70.xyzz, _34._m8.xyzz).xyz;  // 判断范围 isInsideShadow 判断是否在各级联内 // half4 weights = half4(distances2 < _CascadeShadowSplitSphereRadii);
    vec3 _351 = _70.xyz / _34._m8.xyz;              
    _73 = vec4(_351.x, _351.y, _351.z, _73.w); // 13. 计算归一化距离比率 toSphere0.xyz = toCameraVec.xyz / DirShadowSplitSphereRadii.xyz;
    bvec3 _360 = greaterThanEqual(_70.xxyx, _34._m9.xyzx).xyz; // isOutsideClipRange.xyz = (toCameraVec.xxyx >= ShadowMapClipRanges.xyzx).xyz;
    _72 = bvec4(_360.x, _360.y, _360.z, _72.w);       //  检查是否超出裁剪范围
    _70.y = float(_72.x);             // 最远
    _70.z = float(_72.y);
    _70.w = float(_72.z);       // 最近 isOutsideClipRange
    _62.y = float(_78.x);
    _62.z = float(_78.y);
    _62.w = float(_78.z); // isInsideShadow
    _79 = (-_62.xyz) + _62.yzw;        // 
    _70.x = _49.x * _62.z;         // 大于 小于 特殊的一级阴影的范围
    _79 = max(_79, vec3(0.0));     // float3 shadowBlend = max(-isInsideShadow.xyz + isInsideShadow.yzw, float3(0, 0, 0));
    vec3 _405 = vec3(_68) * _79;       //   
    _62 = vec4(_62.x, _405.x, _405.y, _405.z);    // isInsideShadow.yzw = invValidity.xxx * shadowBlend.xyz;
    _68 = dot(_62, vec4(1.0, 4.0, 3.0, 2.0));  // shadowBlend.x  = dot(isInsideShadow, float4(1.0, 4.0, 3.0, 2.0));  // weightedSum 
    _79.x = dot(_73.xyz, _62.yzw); //  float toSphere0Shadow = dot(toSphere0.xyz, isInsideShadow.yzw);
    _79.x = (_79.x * 4.0) + (-3.0); // toSphere0Shadow = toSphere0Shadow * 4.0 - 3.0;
    _79.x = clamp(_79.x, 0.0, 1.0); //  toSphere0Shadow = clamp(toSphere0Shadow, 0.0, 1.0);
    _68 = (-_68) + 4.0;   //  shadowBlend.x   = 4.0 - shadowBlend.x;         // 选择cascade的index
    _84 = max(_68, 0.0);
    _84 = min(_84, 3.0);
    _55 = uint(_84);
    _84 = dot(_70, _8[int(_55)]);  // float dotResult = dot(isOutsideClipRange, ImmCB_0[int(cbIndex)]) // 获取当前是否裁剪
    vec2 _448 = _45 * _38._m0;          // toCameraVec.xy   = vs_TEXCOORD0.xy * ShadowMaskSize.xy;
    _49 = vec4(_448.x, _448.y, _49.z, _49.w);
    _53 = ivec2(_49.xy);  // uint2 pixelCoordInt = (uint2)floor(toCameraVec.xy - epsilon);
    _81 = ivec2(uvec2(_53) & uvec2(2147483648u));       //2147483648u只有最高位为1  
    _53 = max(_53, (-_53));
    _53 = ivec2(uvec2(_53) & uvec2(3u));
    _71 = ivec2(0) - _53;
    ivec2 _476 = _53;
    _476.x = (_81.x != 0) ? _71.x : _53.x;
    _476.y = (_81.y != 0) ? _71.y : _53.y;        // 主要判断正负
    _53 = _476;
    _53 = max(_53, ivec2(0));
    _53.x = (_53.y * 4) + _53.x;       // int ditherIndex = ((pixelCoordInt.y & 0x3) << 2) | (pixelCoordInt.x & 0x3);
    _58 = _79.x >= _34._m3[_53.x];  //     bool shouldDiscard   = (toSphere0Shadow >= DitherFilter[ditherIndex]);
    _79.x = _58 ? _84 : 0.0;        // shouldDiscard ? dotResult : 0.0;        offIndex
    _68 = _79.x + _68;          // offIndex + cascadeindex      相当于discard就选下一级
    _68 = max(_68, 0.0);
    _68 = min(_68, 3.0);
    _55 = uint(_68);
    _53.x = int(_55) << 2;
    _75 = _60.yyy * _34._m0[_53.x + 1].xyz;  //shadowUV.xyz  = WorldToShadowArray[ditherIndex + 1].xyz * scaledDir.yyy;
    _75 = (_34._m0[_53.x].xyz * _60.xxx) + _75;
    _75 = (_34._m0[_53.x + 2].xyz * _60.zzz) + _75;
    vec3 _574 = _75 + _34._m0[_53.x + 3].xyz;
    _49 = vec4(_574.x, _574.y, _574.z, _49.w);
    vec2 _586 = (_49.xy * _34._m17.zz) + vec2(-0.5); // shadowUV * ShadowMapSize.z - 0.5
    _49 = vec4(_586.x, _586.y, _49.z, _49.w);   // shadowUV
    _80 = min(_49.z, 1.0);     // float shadowDepth  = min(scaledDir.z, 1.0);
    vec2 _594 = fract(_49.xy);  // fracUV.xy  = frac(shadowUV.xy);
    _60 = vec3(_594.x, _594.y, _60.z);       // fracUV
    vec2 _599 = floor(_49.xy);         
    _49 = vec4(_599.x, _599.y, _49.z, _49.w); // floorUV = floor(shadowUV.xy);            像素pos
    _83 = (-_60.xy) + vec2(1.0);      // 1- fracUV
    _85 = _34._m17.x * 0.5;        // 0.5 * ShadowMapSize.x
    vec2 _619 = (_49.xy * _34._m17.xx) + vec2(_85);          // 偏移到中心
    _49 = vec4(_619.x, _619.y, _49.z, _49.w);
    _61 = (_34._m17.xxxx * vec4(2.0, -2.0, 2.0, 0.0)) + _49.xyxy;  // 左上角 中上
    _66 = textureGather(_42, _61.xy);
    _61 = textureGather(_42, _61.zw);
    _65 = greaterThanEqual(_61, vec4(_80));                        //Manual5x5PCF      unreal  覆盖了6*6个像素只是边缘一圈的像素部分占比
    _61.x = float(_65.x);
    _61.y = float(_65.y);
    _61.z = float(_65.z);
    _61.w = float(_65.w);
    _69 = greaterThanEqual(_66, vec4(_80));
    _66.x = float(_69.x);
    _66.y = float(_69.y);
    _66.z = float(_69.z);
    _66.w = float(_69.w);
    _70 = (_34._m17.xxxx * vec4(-2.0, -2.0, 0.0, -2.0)) + _49.xyxy;
    _73 = textureGather(_42, _70.zw);
    _70 = textureGather(_42, _70.xy);
    _72 = greaterThanEqual(_70, vec4(_80));
    _70.x = float(_72.x);
    _70.y = float(_72.y);
    _70.z = float(_72.z);
    _70.w = float(_72.w);
    vec2 _722 = (_70.wx * _83.xx) + _70.zy;
    _70 = vec4(_722.x, _722.y, _70.z, _70.w);
    _74 = greaterThanEqual(_73, vec4(_80));
    _73.x = float(_74.x);
    _73.y = float(_74.y);
    _73.z = float(_74.z);
    _73.w = float(_74.w);
    vec2 _749 = _70.xy + _73.wx;
    _70 = vec4(_749.x, _749.y, _70.z, _70.w);
    vec2 _756 = _73.zy + _70.xy;
    _70 = vec4(_756.x, _756.y, _70.z, _70.w);
    vec2 _763 = _66.wx + _70.xy;
    _70 = vec4(_763.x, _763.y, _70.z, _70.w);
    vec2 _773 = (_66.zy * _60.xx) + _70.xy;
    _70 = vec4(_773.x, _773.y, _70.z, _70.w);
    _85 = (_70.x * _83.y) + _70.y;
    _66 = textureGather(_42, _49.xy);
    _69 = greaterThanEqual(_66, vec4(_80));
    _66.x = float(_69.x);
    _66.y = float(_69.y);
    _66.z = float(_69.z);
    _66.w = float(_69.w);
    vec2 _815 = (_34._m17.xx * vec2(-2.0, 0.0)) + _49.xy;
    _70 = vec4(_815.x, _815.y, _70.z, _70.w);
    _70 = textureGather(_42, _70.xy);
    _72 = greaterThanEqual(_70, vec4(_80));
    _70.x = float(_72.x);
    _70.y = float(_72.y);
    _70.z = float(_72.z);
    _70.w = float(_72.w);
    vec2 _849 = (_70.wx * _83.xx) + _70.zy;
    _70 = vec4(_849.x, _849.y, _70.z, _70.w);
    vec2 _856 = _66.wx + _70.xy;
    _70 = vec4(_856.x, _856.y, _70.z, _70.w);
    vec2 _863 = _66.zy + _70.xy;
    _70 = vec4(_863.x, _863.y, _70.z, _70.w);
    vec2 _870 = _61.wx + _70.xy;
    _70 = vec4(_870.x, _870.y, _70.z, _70.w);
    vec2 _880 = (_61.zy * _60.xx) + _70.xy;
    _70 = vec4(_880.x, _880.y, _70.z, _70.w);
    _87 = _70.y + _70.x;
    _85 += _87;
    _61 = (_34._m17.xxxx * vec4(-2.0, 2.0, 0.0, 2.0)) + _49.xyxy;
    vec2 _905 = (_34._m17.xx * vec2(2.0)) + _49.xy;
    _49 = vec4(_905.x, _905.y, _49.z, _49.w);
    _66 = textureGather(_42, _49.xy);
    _69 = greaterThanEqual(_66, vec4(_80));
    _66.x = float(_69.x);
    _66.y = float(_69.y);
    _66.z = float(_69.z);
    _66.w = float(_69.w);
    _70 = textureGather(_42, _61.xy);
    _61 = textureGather(_42, _61.zw);
    _65 = greaterThanEqual(_61, vec4(_80));
    _72 = greaterThanEqual(_70, vec4(_80));
    _70.x = float(_72.x);
    _70.y = float(_72.y);
    _70.z = float(_72.z);
    _70.w = float(_72.w);
    vec2 _971 = (_70.wx * _83.xx) + _70.zy;
    _49 = vec4(_971.x, _971.y, _49.z, _49.w);
    _61.x = float(_65.x);
    _61.y = float(_65.y);
    _61.z = float(_65.z);
    _61.w = float(_65.w);
    vec2 _994 = _49.xy + _61.wx;
    _49 = vec4(_994.x, _994.y, _49.z, _49.w);
    vec2 _1001 = _61.zy + _49.xy;
    _49 = vec4(_1001.x, _1001.y, _49.z, _49.w);
    vec2 _1008 = _66.wx + _49.xy;
    _49 = vec4(_1008.x, _1008.y, _49.z, _49.w);
    vec2 _1018 = (_66.zy * _60.xx) + _49.xy;
    _49 = vec4(_1018.x, _1018.y, _49.z, _49.w);
    _49.x = (_49.y * _60.y) + _49.x;
    _49.x += _85;
    _49.x *= 0.039999999105930328369140625;    // 1 / 25
    _47 = _49.x * _49.x;
}

void main()
{
    float _1078 = 0.0;
    _96();
    if (_2 != 0u)
    {
        _1074 = _1056[((uint(gl_FragCoord.x) & 1u) << 1u) | (uint(gl_FragCoord.y) & 1u)];
        _1077 = (_2 >> 0u) & 3u;
        switch (_1077)
        {
            case 1u:
            {
                _1078 = _1074 * 2.0;
                _1081 = vec3(15.0);
                break;
            }
            case 2u:
            {
                _1078 = _1074;
                _1081 = vec3(31.0);
                break;
            }
            case 3u:
            {
                _1078 = _1074;
                _1081 = vec3(31.0, 63.0, 31.0);
                break;
            }
        }
        _47 += _1078;
        _47 = round(_47 * _1081.x) / _1081.x;
    }
}


//写入线性深度 和 深度buffer  二分之一分辨率
layout(location = 0) out vec2 _9;
vec3 _11;
uint _14;
vec2 _16;
uint _17;
vec4 _26;

void main()
{
    _14 = uint(gl_VertexIndex) & 2u;
    _11.y = float(_14);
    _11.z = (-_11.y) + 1.0;
    _17 = uint(bitfieldInsert(0, gl_VertexIndex, 1, 1));
    _11.x = float(_17);
    _16 = (_11.xz * vec2(2.0)) + vec2(-1.0);
    _9 = _11.xy;
    gl_Position.y = _16.y * (-_6._m8.x);
    gl_Position.x = _16.x;
    gl_Position = vec4(gl_Position.x, gl_Position.y, vec2(-1.0, 1.0).x, vec2(-1.0, 1.0).y);
}

layout(location = 0) in vec2 _15;
layout(location = 0) out vec4 _17;    //线性深度
vec4 _19;
float _21;
float _108;
uint _112;
vec3 _119 = vec3(255.0);

void _31()
{
    _19 = textureGather(_12, _15);
    _21 = (_8._m10.z * _19.w) + _8._m10.w;
    _17 = vec4(1.0) / vec4(_21); //线性深度
    _19.x = max(_19.y, _19.x);
    _19.x = max(_19.x, _19.z);
    gl_FragDepth = max(_19.x, _19.w);  // maxDepth
}

//通过线性深度 获取 // ssao
layout(location = 1) out vec2 _9;   // uv
vec4 _11;
uvec4 _15;
vec4 _23;

void main()
{
    _15.x = uint(bitfieldInsert(0, gl_VertexIndex, 1, 1));
    _15.w = uint(gl_VertexIndex) & 2u;
    vec2 _52 = vec2(_15.xw);
    _11 = vec4(_52.x, _52.y, _11.z, _11.w);
    _9 = _11.xy;
    _11.z = (-_11.y) + 1.0;
    vec2 _72 = (_11.xz * vec2(2.0)) + vec2(-1.0);
    _11 = vec4(_72.x, _72.y, _11.z, _11.w);
    _11.z = _11.y * (-_6._m8.x);
    _11.w = 1.0;
    gl_Position = _11.xzww;
}

#version 460

layout(constant_id = 4) const uint _2 = 0u;
layout(constant_id = 2) const float _4 = 0.0;
layout(constant_id = 3) const float _5 = 0.0;
layout(constant_id = 1) const uint _6 = 0u;

struct _59
{
    float _m0;
    float _m1;
    float _m2;
    float _m3;
};

const vec2 _84[8] = vec2[](vec2(1.0), vec2(1.0), vec2(-1.0, 1.0), vec2(-1.0), vec2(1.0, -1.0), vec2(1.0), vec2(-1.0, 1.0), vec2(-1.0));
const float _1080[4] = float[](-0.01171875, 0.00390625, 0.01171875, -0.00390625);

layout(set = 3, binding = 1, std140) uniform _12_14
{
    vec4 _m0[4];
    vec4 _m1;
    vec4 _m2;
    vec4 _m3;
    vec4 _m4;
    vec4 _m5;
    vec4 _m6;
} _14;

layout(set = 0, binding = 0, std140) uniform _60_62
{
    vec4 _m0;
    uint _m1;
    uint _m2;
    int _m3;
    int _m4;
    ivec4 _m5;
    uvec4 _m6;
    _59 _m7;
} _62;

layout(set = 2, binding = 0) uniform sampler2D _18;

layout(location = 1) in vec2 _21;    // uv
layout(location = 0) out vec4 _23;
vec4 _9;
vec4 _24;
vec4 _25;
float _27;
vec4 _28;
vec4 _29;
vec4 _30;
vec4 _31;
vec4 _32;
vec4 _33;
vec4 _34;
vec4 _35;
vec4 _36;
vec4 _37;
vec4 _38;
vec4 _39;
vec2 _41;
vec4 _42;
float _43;
vec3 _46;
vec3 _47;
bvec2 _51;
float _52;
vec2 _53;
vec2 _54;
float _55;
float _1096;
uint _1100;
vec3 _1106 = vec3(255.0);

void _65()
{
    _9 = gl_FragCoord;
    vec2 _93 = ((gl_FragCoord.xy - (vec2(_4, _5) * 0.5)) * _84[_6]) + (vec2(_4, _5) * 0.5);
    _9 = vec4(_93.x, _93.y, _9.z, _9.w);    // screenPos
    vec4 _107 = vec4(_9.xyz, 1.0 / _9.w);   // 
    _24 = _21.xyxy + _14._m4;           // uv + 偏移  (0.5 * screensize.xy)
    _53 = textureGather(_18, _24.zw).xz;         //  见https://microsoft.github.io/DirectX-Specs/d3d/archive/D3D11_3_FunctionalSpec.htm#inst_GATHER4
    vec2 _124 = textureGather(_18, _24.xy).xz;   // 
    _24 = vec4(_124.x, _124.y, _24.z, _24.w);
    _27 = texture(_18, _21).x;
    vec2 _135 = _53 + (-vec2(_27));       
    _47 = vec3(_135.x, _135.y, _47.z);  // 深度差 D(x-1, y) - D(x,y) ,  D(x, y - 1) - D(x,y)
    vec2 _143 = _24.yx + (-vec2(_27));
    _29 = vec4(_143.x, _143.y, _29.z, _29.w); // 深度差 D(x + 1, y) - D(x,y) ,  D(x, y + 1) - D(x,y)
    _51 = lessThan(abs(_47.xyxx), abs(_29.xyxx)).xy;    // 选择稳定方向构建 xz < zx 相当于 横向derive 纵向derive 左右的区别
    _29 = _21.xyxy + (-_14._m3);    // _21.xyxy - screensize.x00y     左  下
    _29 = (_29.wxzy * _14._m1.yxxy) + _14._m1.wzzw;      //左下  原坐标   获取世界坐标
    _31 = vec4(_31.x, _29.yw.x, _29.yw.y, _31.w);   // 左
    _31.x = -1.0;
    vec2 _188 = (_21.yx * _14._m1.yx) + _14._m1.wz; //缩放偏移  原来位置
    _32 = vec4(_188.x, _32.y, _188.y, _32.w);
    _32.y = -1.0;
    vec3 _196 = vec3(_27) * _32.xyz;         // depth   
    _32 = vec4(_196.x, _32.y, _196.y, _196.z);  // 原来位置
    vec3 _207 = ((-_31.xyz) * _53.xxx) + _32.zwx;            // _53.x 左(x- 1, y)          // 原来位置 - 左
    _31 = vec4(_207.x, _207.y, _207.z, _31.w);  // 1
    _33 = _21.xyxy + _14._m3;             // 缩放偏移    右
    _33 = (_33.wxzy * _14._m1.yxxy) + _14._m1.wzzw;
    _35 = vec4(_35.x, _33.yw.x, _33.yw.y, _35.w);
    _35.x = -1.0;
    vec3 _238 = (_35.xyz * _24.yyy) + (-_32.zwx);  // 右 - 原来位置
    _35 = vec4(_238.x, _238.y, _238.z, _35.w);
    vec3 _250 = mix(_35.xyz, _31.xyz, bvec3(_51.x)); // DeviceZDdx       选择
    _31 = vec4(_250.x, _250.y, _250.z, _31.w);
    _29.y = -1.0;
    _46 = ((-_29.xyz) * _53.yyy) + _32.xzw;
    _33.y = -1.0;
    vec3 _272 = (_33.xyz * _24.xxx) + (-_32.xzw);
    _29 = vec4(_272.x, _272.y, _272.z, _29.w);
    vec3 _281 = mix(_29.xyz, _46, bvec3(_51.y));   // DeviceZDdx
    _24 = vec4(_281.x, _281.y, _281.z, _24.w);
    _47 = _24.xyz * _31.xyz;
    vec3 _296 = (_31.zxy * _24.yzx) + (-_47);      // corss       横向 纵向梯度
    _24 = vec4(_296.x, _296.y, _296.z, _24.w);   // normal         // https://zhuanlan.zhihu.com/p/367257314上  述见这里由于uv*2 - 1，所以是缩放偏移
    _55 = dot(_24.xyz, _24.xyz);
    _55 = inversesqrt(_55);
    vec3 _310 = vec3(_55) * _24.xyz;
    _24 = vec4(_310.x, _310.y, _310.z, _24.w); // normal
    _55 = dot(_107.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125));//unreal InterleavedGradientNoise
    _55 = fract(_55);
    _55 *= 52.98291778564453125;
    _55 = fract(_55);           // unreal InterleavedGradientNoise
    _38.x = _55 * 3.1415927410125732421875;  // GetRandomVector(int2 TexturePos)
    _41.x = cos(_38.x);      //  cos((GradientNoise*PI));
    _38.x = sin(_38.x);
    _41.y = _38.x;              // RandomTexVec
    vec2 _346 = _41 * _14._m2.zw;  // 
    _47 = vec3(_346.x, _346.y, _47.z);// texsize.zw * RandomTexVec
    _38.x = (-_107.x) + _107.y;  //               
    _38.x *= 0.25;             // 下面是抖动加 十字核采样(现代已被其他替代) 往外扩 12个采样 // Fast Fake Global Illumination //  https://www.gamedev.net/tutorials/programming/graphics/a-simple-and-practical-approach-to-ssao-r2753/
    _38.x = fract(_38.x);      // float jitter = frac((screenPos.y - screenPos.x) * 0.25);  见unreal ssao GetRandomVector
    _55 = _14._m5.y / _27; // float depthScale = baseRadius / linearDepth;  //  max(min(WorldRadiusAdj / ViewSpacePos.z, GTAO_MAX_PIXEL_SCREEN_RADIUS), (half)GTAO_NUMTAPS);
    _55 = min(_55, 12.5);  // depthScale = min(depthScale, 12.5); // 限制最大半径     //Scalable Ambient Obscurance  随机旋转采样核 + 深度缩放半径
    _38.x = (_38.x * _55) + 2.0;   //   float sampleRadius = jitter * depthScale + 2.0;
    vec3 _386 = vec3(_55) * _47.xyx;    
    _30 = vec4(_386.x, _386.y, _30.z, _386.z); // depthScale * RandomTexVec        noJitter      
    vec2 _395 = (_47.xy * _38.xx) + _21;  // 
    _31 = vec4(_395.x, _395.y, _31.z, _31.w); //sampleUV  sampleRadius * RandomTexVec + uv     
    _55 = texture(_18, _31.xy).x;       // 随机采样深度
    _33.z = ((-_32.y) * _27) + (-_55);   // 深度差
    _54.x = (-_47.y) * _38.x;
    _54.y = _47.x * _38.x;       
    vec2 _432 = ((-_47.xy) * _38.xx) + _21;          
    _35 = vec4(_432.x, _432.y, _35.z, _35.w);     //  --
    vec2 _437 = _54 + _21;                              
    _31 = vec4(_31.x, _31.y, _437.x, _437.y);       // +-
    vec2 _443 = (-_54) + _21;                               
    _35 = vec4(_35.x, _35.y, _443.x, _443.y);  // -+
    _37 = (_31 * _14._m1.xyxy) + _14._m1.zwzw;     // 
    vec2 _463 = (_37.xy * vec2(_55)) + (-_32.wx);   
    _33 = vec4(_463.x, _463.y, _33.z, _33.w);  //  ++ - 原来位置
    _39.x = dot(_33.xyz, _24.xyz);        // dot(++ - 原来位置, normal)
    _33.x = dot(_33.xyz, _33.xyz); // dot(++ - 原来位置, ++ - 原来位置)
    _55 = texture(_18, _31.zw).x;     // +-
    _42.z = ((-_32.y) * _27) + (-_55);  // 深度差
    vec2 _500 = (_37.zw * vec2(_55)) + (-_32.wx);
    _42 = vec4(_500.x, _500.y, _42.z, _42.w);
    _39.y = dot(_42.xyz, _24.xyz);
    _33.y = dot(_42.xyz, _42.xyz);   // 类似dot(+- - 原来位置, +- - 原来位置)
    _55 = texture(_18, _35.xy).x;
    _42.z = ((-_32.y) * _27) + (-_55);
    _37 = (_35 * _14._m1.xyxy) + _14._m1.zwzw;
    vec2 _546 = (_37.xy * vec2(_55)) + (-_32.wx);
    _42 = vec4(_546.x, _546.y, _42.z, _42.w);
    _39.z = dot(_42.xyz, _24.xyz);
    _33.z = dot(_42.xyz, _42.xyz);     //  类似dot(-- - 原来位置, -- - 原来位置)
    _55 = texture(_18, _35.zw).x;
    _42.z = ((-_32.y) * _27) + (-_55);
    vec2 _583 = (_37.zw * vec2(_55)) + (-_32.wx);
    _42 = vec4(_583.x, _583.y, _42.z, _42.w);
    _39.w = dot(_42.xyz, _24.xyz);
    _33.w = dot(_42.xyz, _42.xyz);     //  类似dot(-+ - 原来位置, -+ - 原来位置) dist
    _37 = inversesqrt(_33);
    _34 = (_33 * _14._m5.wwww) + vec4(1.0);
    _34 = clamp(_34, vec4(0.0), vec4(1.0));  // 
    _38 = (_39 * _37) + (-_14._m5.zzzz);      // nomalCos - _14._m5.zzzz
    _38 = clamp(_38, vec4(0.0), vec4(1.0));
    _34 *= _38;           //  (nomalCos - _14._m5.zzzz) * (dist *_14._m5.wwww  + 1)
    _43 = dot(_34, vec4(1.0)); // AO
    _30.z = -_30.y;                         // ++ 和垂直的位移
    _31 = _30 + _31;                 // noJitter 的4个
    _55 = texture(_18, _31.xy).x;    
    _42.z = ((-_32.y) * _27) + (-_55);
    _33 = (_31 * _14._m1.xyxy) + _14._m1.zwzw;
    vec2 _667 = (_33.xy * vec2(_55)) + (-_32.wx);
    _42 = vec4(_667.x, _667.y, _42.z, _42.w);
    _37.x = dot(_42.xyz, _42.xyz);
    _39.x = dot(_42.xyz, _24.xyz);
    _55 = texture(_18, _31.zw).x;
    _31 = _30 + _31;
    _42.z = ((-_32.y) * _27) + (-_55);
    vec2 _707 = (_33.zw * vec2(_55)) + (-_32.wx);
    _42 = vec4(_707.x, _707.y, _42.z, _42.w);
    _37.y = dot(_42.xyz, _42.xyz);
    _39.y = dot(_42.xyz, _24.xyz);
    _33 = (-_30.wyzw) + _35;
    _29 = (-_30.wyzw) + _33;
    _55 = texture(_18, _33.xy).x;
    _35.z = ((-_32.y) * _27) + (-_55);
    _42 = (_33 * _14._m1.xyxy) + _14._m1.zwzw;
    _47.x = texture(_18, _33.zw).x;
    vec2 _769 = (_42.xy * vec2(_55)) + (-_32.wx);
    _35 = vec4(_769.x, _769.y, _35.z, _35.w);
    vec2 _780 = (_42.zw * _47.xx) + (-_32.wx);
    _42 = vec4(_780.x, _780.y, _42.z, _42.w);
    _42.z = ((-_32.y) * _27) + (-_47.x);
    _37.z = dot(_35.xyz, _35.xyz);
    _39.z = dot(_35.xyz, _24.xyz);
    _37.w = dot(_42.xyz, _42.xyz);
    _39.w = dot(_42.xyz, _24.xyz);
    _33 = inversesqrt(_37);
    _36 = (_37 * _14._m5.wwww) + vec4(1.0);
    _36 = clamp(_36, vec4(0.0), vec4(1.0));
    _34 = (_39 * _33) + (-_14._m5.zzzz);
    _34 = clamp(_34, vec4(0.0), vec4(1.0));
    _34 = _36 * _34;
    _52 = dot(_34, vec4(1.0));
    _43 = _52 + _43;
    _55 = texture(_18, _31.xy).x;
    _42.z = ((-_32.y) * _27) + (-_55);
    _33 = (_31 * _14._m1.xyxy) + _14._m1.zwzw;
    _47.x = texture(_18, _31.zw).x;
    vec2 _886 = (_33.xy * vec2(_55)) + (-_32.wx);
    _42 = vec4(_886.x, _886.y, _42.z, _42.w);
    vec2 _897 = (_33.zw * _47.xx) + (-_32.wx);
    _31 = vec4(_897.x, _897.y, _31.z, _31.w);
    _31.z = ((-_32.y) * _27) + (-_47.x);
    _33.x = dot(_42.xyz, _42.xyz);
    _35.x = dot(_42.xyz, _24.xyz);
    _33.y = dot(_31.xyz, _31.xyz);
    _35.y = dot(_31.xyz, _24.xyz);
    _55 = texture(_18, _29.xy).x;
    _31.z = ((-_32.y) * _27) + (-_55);
    _37 = (_29 * _14._m1.xyxy) + _14._m1.zwzw;
    _47.x = texture(_18, _29.zw).x;
    vec2 _971 = (_37.xy * vec2(_55)) + (-_32.wx);
    _31 = vec4(_971.x, _971.y, _31.z, _31.w);
    vec2 _982 = (_37.zw * _47.xx) + (-_32.wx);
    _42 = vec4(_982.x, _982.y, _42.z, _42.w);
    _42.z = ((-_32.y) * _27) + (-_47.x);
    _23.y = _27;
    _33.z = dot(_31.xyz, _31.xyz);
    _35.z = dot(_31.xyz, _24.xyz);
    _35.w = dot(_42.xyz, _24.xyz);
    _33.w = dot(_42.xyz, _42.xyz);
    _24 = inversesqrt(_33);
    _28 = (_33 * _14._m5.wwww) + vec4(1.0);
    _28 = clamp(_28, vec4(0.0), vec4(1.0));
    _25 = (_35 * _24) + (-_14._m5.zzzz);
    _25 = clamp(_25, vec4(0.0), vec4(1.0));
    _25 = _28 * _25;
    _52 = dot(_25, vec4(1.0));
    _43 = _52 + _43;
    _23.x = ((-_43) * _14._m6.y) + 1.0;     // ao强度
    _23.x = clamp(_23.x, 0.0, 1.0);
    _23 = vec4(_23.x, _23.y, vec2(0.0).x, vec2(0.0).y);
}


// ssao  normal texture   不用从depth buffer 重构normal
void _69()
{
    _9 = gl_FragCoord;
    vec2 _97 = ((gl_FragCoord.xy - (vec2(_4, _5) * 0.5)) * _88[_6]) + (vec2(_4, _5) * 0.5);
    _9 = vec4(_97.x, _97.y, _9.z, _9.w);   // screenPos
    vec4 _111 = vec4(_9.xyz, 1.0 / _9.w);
    _25.x = dot(_111.xy, vec2(0.067110560834407806396484375, 0.005837149918079376220703125));  // unreal InterleavedGradientNoise
    _25.x = fract(_25.x);
    _25.x *= 52.98291778564453125;
    _25.x = fract(_25.x);
    _31.x = _25.x * 3.1415927410125732421875;
    _33.x = cos(_31.x);
    _31.x = sin(_31.x);
    _33.y = _31.x;
    vec2 _158 = _33.xy * _14._m2.zw;
    _25 = vec4(_158.x, _158.y, _25.z, _25.w);
    _31.x = (-_111.x) + _111.y;
    _31.x *= 0.25;           //// 下面是抖动加 十字核采样
    _31.x = fract(_31.x);
    _56 = texture(_19, _22).x;
    _54 = _14._m5.y / _56;
    _54 = min(_54, 12.5);
    _31.x = (_31.x * _54) + 2.0;
    vec3 _202 = _25.xyx * vec3(_54);
    _33 = vec4(_202.x, _202.y, _33.z, _202.z);
    _57.x = (-_25.y) * _31.x;
    _57.y = _25.x * _31.x;
    vec2 _220 = _57 + _22;
    _34 = vec4(_34.x, _34.y, _220.x, _220.y);
    vec2 _226 = (-_57) + _22;
    _36 = vec4(_36.x, _36.y, _226.x, _226.y);
    vec2 _235 = (_25.xy * _31.xx) + _22;
    _34 = vec4(_235.x, _235.y, _34.z, _34.w);
    vec2 _245 = ((-_25.xy) * _31.xx) + _22;
    _36 = vec4(_245.x, _245.y, _36.z, _36.w);
    _30 = (_34 * _14._m1.xyxy) + _14._m1.zwzw;
    _26.x = texture(_19, _34.xy).x;
    vec2 _271 = (_22 * _14._m1.xy) + _14._m1.zw;
    _53 = vec3(_271.x, _53.y, _271.y);
    vec2 _278 = vec2(_56) * _53.xz;
    _53 = vec3(_278.x, _53.y, _278.y);
    vec2 _289 = (_30.xy * _26.xx) + (-_53.xz);
    _38 = vec4(_289.x, _289.y, _38.z, _38.w);
    _24.y = _56;
    _38.z = _56 + (-_26.x);
    _41.x = dot(_38.xyz, _38.xyz);
    _26.x = texture(_19, _34.zw).x;
    vec2 _321 = (_30.zw * _26.xx) + (-_53.xz);
    _45 = vec3(_321.x, _321.y, _45.z);
    _45.z = _56 + (-_26.x);
    _41.y = dot(_45, _45);
    _26.x = texture(_19, _36.xy).x;
    _30 = (_36 * _14._m1.xyxy) + _14._m1.zwzw;
    vec2 _357 = (_30.xy * _26.xx) + (-_53.xz);
    _46 = vec3(_357.x, _357.y, _46.z);
    _46.z = _56 + (-_26.x);
    _41.z = dot(_46, _46);
    _26.x = texture(_19, _36.zw).x;
    vec2 _384 = (_30.zw * _26.xx) + (-_53.xz);
    _47 = vec3(_384.x, _384.y, _47.z);
    _47.z = _56 + (-_26.x);
    _41.w = dot(_47, _47);
    _30 = inversesqrt(_41);
    _42 = (_41 * _14._m5.wwww) + vec4(1.0);
    _42 = clamp(_42, vec4(0.0), vec4(1.0));
    vec2 _418 = ((-_14._m2.zw) * vec2(0.25)) + _22;   // uv - texelsize.xy * 0.25
    _48 = vec3(_418.x, _418.y, _48.z);
    _49 = texture(_18, _48.xy).xyz;          // noramlTexture 
    _50 = (_49 * vec3(2.0)) + vec3(-1.0); 
    _29 = int((0.0 < _50.z) ? 4294967295u : 0u);
    _59 = int((_50.z < 0.0) ? 4294967295u : 0u);
    _29 = (-_29) + _59;
    _58 = float(_29);         // sign 正负
    _60 = dot(_50.xy, _50.xy);         // x^2 + y^2
    vec2 _458 = _50.xy + _50.xy;
    _50 = vec3(_458.x, _458.y, _50.z);
    _52 = vec2(_60) + vec2(1.0, -1.0);
    _60 = _52.y / _52.x;        // (x^2 + y ^2 - 1) / (x^2 + y ^2 + 1)     
    vec2 _473 = _50.xy / _52.xx;   //  2 * (x, y )/ (x^2 + y ^2 + 1)     
    _50 = vec3(_473.x, _473.y, _50.z);
    _58 = (-_58) * _60;                     // decode noraml          stereographic projection
    _48 = _50.yyy * _14._m0[1u].xyz;
    _48 = (_14._m0[0u].xyz * _50.xxx) + _48;
    _48 = (_14._m0[2u].xyz * vec3(_58)) + _48;  // view space normal
    _38.x = dot(_38.xyz, _48);
    _38.y = dot(_45, _48);
    _38.z = dot(_46, _48);
    _38.w = dot(_47, _48);
    _31 = (_38 * _30) + (-_14._m5.zzzz);
    _31 = clamp(_31, vec4(0.0), vec4(1.0));
    _31 = _42 * _31;
    _50.x = dot(_31, vec4(1.0));
    _33.z = -_33.y;
    _30 = _33 + _34;
    _26.x = texture(_19, _30.xy).x;
    _34 = (_30 * _14._m1.xyxy) + _14._m1.zwzw;
    vec2 _567 = (_34.xy * _26.xx) + (-_53.xz);
    _38 = vec4(_567.x, _567.y, _38.z, _38.w);
    _38.z = _56 + (-_26.x);
    _41.x = dot(_38.xyz, _38.xyz);
    _38.x = dot(_38.xyz, _48);
    _26.x = texture(_19, _30.zw).x;
    _30 = _33 + _30;
    vec2 _604 = (_34.zw * _26.xx) + (-_53.xz);
    _34 = vec4(_604.x, _604.y, _34.z, _34.w);
    _34.z = _56 + (-_26.x);
    _41.y = dot(_34.xyz, _34.xyz);
    _38.y = dot(_34.xyz, _48);
    _34 = (-_33.wyzw) + _36;
    _32 = (-_33.wyzw) + _34;
    _26.x = texture(_19, _34.xy).x;
    _36 = (_34 * _14._m1.xyxy) + _14._m1.zwzw;
    _35.x = texture(_19, _34.zw).x;
    vec2 _663 = (_36.xy * _26.xx) + (-_53.xz);
    _45 = vec3(_663.x, _663.y, _45.z);
    _45.z = _56 + (-_26.x);
    vec2 _680 = (_36.zw * _35.xx) + (-_53.xz);
    _36 = vec4(_680.x, _680.y, _36.z, _36.w);
    _36.z = _56 + (-_35.x);
    _41.z = dot(_45, _45);
    _38.z = dot(_45, _48);
    _41.w = dot(_36.xyz, _36.xyz);
    _38.w = dot(_36.xyz, _48);
    _34 = inversesqrt(_41);
    _37 = (_41 * _14._m5.wwww) + vec4(1.0);
    _37 = clamp(_37, vec4(0.0), vec4(1.0));
    _35 = (_38 * _34) + (-_14._m5.zzzz);
    _35 = clamp(_35, vec4(0.0), vec4(1.0));
    _35 = _37 * _35;
    _55 = dot(_35, vec4(1.0));
    _50.x = _55 + _50.x;
    _26.x = texture(_19, _30.xy).x;
    _34 = (_30 * _14._m1.xyxy) + _14._m1.zwzw;
    _40 = texture(_19, _30.zw).x;
    vec2 _770 = (_34.xy * _26.xx) + (-_53.xz);
    _45 = vec3(_770.x, _770.y, _45.z);
    _45.z = _56 + (-_26.x);
    vec2 _787 = (_34.zw * vec2(_40)) + (-_53.xz);
    _46 = vec3(_787.x, _787.y, _46.z);
    _46.z = _56 + (-_40);
    _30.x = dot(_45, _45);
    _34.x = dot(_45, _48);
    _30.y = dot(_46, _46);
    _34.y = dot(_46, _48);
    _26.x = texture(_19, _32.xy).x;
    _36 = (_32 * _14._m1.xyxy) + _14._m1.zwzw;
    _40 = texture(_19, _32.zw).x;
    vec2 _839 = (_36.xy * _26.xx) + (-_53.xz);
    _45 = vec3(_839.x, _839.y, _45.z);
    _45.z = _56 + (-_26.x);
    _46.z = _56 + (-_40);
    vec2 _861 = (_36.zw * vec2(_40)) + (-_53.xz);
    _46 = vec3(_861.x, _861.y, _46.z);
    _30.z = dot(_45, _45);
    _34.z = dot(_45, _48);
    _34.w = dot(_46, _48);
    _30.w = dot(_46, _46);
    _25 = inversesqrt(_30);
    _31 = (_30 * _14._m5.wwww) + vec4(1.0);
    _31 = clamp(_31, vec4(0.0), vec4(1.0));
    _26 = (_34 * _25) + (-_14._m5.zzzz);
    _26 = clamp(_26, vec4(0.0), vec4(1.0));
    _26 = _31 * _26;
    _55 = dot(_26, vec4(1.0));
    _50.x = _55 + _50.x;
    _24.x = ((-_50.x) * _14._m6.y) + 1.0;
    _24.x = clamp(_24.x, 0.0, 1.0);
    _24 = vec4(_24.x, _24.y, vec2(0.0).x, vec2(0.0).y);
}

// 
// ssao blur pass
layout(set = 2, binding = 0) uniform sampler2D _12;

layout(location = 0) in vec2 _14;    // uv
layout(location = 0) out vec4 _16;
vec4 _18;
float _20;
vec4 _21;
float _22;
float _23;
float _181;
uint _185;
vec3 _191 = vec3(255.0);

void _33()
{
    _18 = (_8._m0.xyxy * vec4(-1.5, -1.5, -1.5, 1.5)) + _14.xyxy;    // uv + texelsize.xyxy * float4(-1.5, -1.5, -1.5, 1.5)    -- -+
    _21.x = texture(_12, _18.xy).x;
    _21.y = texture(_12, _18.zw).x;
    _18 = (_8._m0.xyxy * vec4(1.5, -1.5, 1.5, 1.5)) + _14.xyxy;       // +- ++
    _21.z = texture(_12, _18.xy).x;
    _21.w = texture(_12, _18.zw).x;
    _22 = dot(_21, vec4(0.1599999964237213134765625));      // weight 和
    _20 = texture(_12, _14).x;                                      //00                        [ 4, 2, 4 ]
    _22 = (_20 * 0.039999999105930328369140625) + _22;        // 求和                            [ 2, 1, 2 ]
    _18 = (_8._m0.xyxy * vec4(-1.5, -0.0, 1.5, -0.0)) + _14.xyxy;  // -0  +0                    [ 4, 2, 4 ]  奇怪的blur kernel  
    _21.x = texture(_12, _18.xy).x;                                                          // 中间下相当于隐含了“反拉普拉斯”的特性削弱高频分量方面会比标准的均值核更有效
    _21.y = texture(_12, _18.zw).x;
    _18 = (_8._m0.xyxy * vec4(-0.0, -1.5, -0.0, 1.5)) + _14.xyxy;   // 0-  0+
    _21.z = texture(_12, _18.xy).x;
    _21.w = texture(_12, _18.zw).x;
    _23 = dot(_21, vec4(0.07999999821186065673828125));  // 求和
    _16.x = _23 + _22; // 求和
    _16 = vec4(_16.x, vec3(0.0).x, vec3(0.0).y, vec3(0.0).z);           // blur结果
}


// 填写深度buffer   // 写入了stencil
void main()
{
    _11 = textureGather(_5, _8);
    _11.x = max(_11.y, _11.x);
    _11.x = max(_11.x, _11.z);
    gl_FragDepth = max(_11.x, _11.w);
}

// AO + cascade shadow      // 不考虑阴影过渡区域  获取半分辨率的阴影  写入stencil提高效率
layout(set = 2, binding = 0) uniform sampler2D _20;      // AOTexture
layout(set = 2, binding = 1) uniform sampler2D _21;      // cascadeShadowTexture

layout(location = 0) in vec2 _24;         // uv
layout(location = 0) out vec4 _26;
vec4 _28;
float _30;
bool _33;
float _34;
bool _35;
float _136;
uint _140;
vec3 _148 = vec3(255.0);

void _45()
{
    _28 = textureGather(_21, _24);
    _28.x = _28.y + _28.x;
    _28.x = _28.z + _28.x;
    _28.x = _28.w + _28.x;
    _34 = _28.x * 0.25;                // shadow
    _33 = 0.039999999105930328369140625 < _28.x;            // sumS > 0.04
    _35 = _34 < _16._m19;           // shadow < 0.9
    _33 = _35 && _33;    // 阴影过渡区域
    if (_33)
    {
        discard;      // 过渡区域丢弃掉
    }
    _30 = texture(_20, _24).x;            // AO
    _26 = vec4(_26.x, vec2(1.0).x, vec2(1.0).y, _26.w);
    _26.w = _30; // AO
    _26.x = _34;  // shadow
}

// ssao + pcf的shadow    //执行stencil test 避免重复写入  // 这里对过渡区域获取精确的pcf shadow  ，性能优化
{
    pcf相关 
    _52 = texture(_44, _46).x;  // AO
    _48.w = _52;       // AO
    _48 = vec4(_48.x, vec2(1.0).x, vec2(1.0).y, _48.w);          // shadow ao
}

//输出 r 是 常规cascade shadow  g 是一个单独的soft shadow   a是 AO
// 另一个  soft shadow         pcf shadow的变体， 把采样随机旋转     只写入g通道
layout(location = 0) in vec2 _20;
layout(location = 0) out vec4 _22;
vec4 _24;
vec4 _25;
float _27;
vec4 _35;

void main()
{
    _24 = vec4(_20.x, _20.y, _24.z, _24.w);
    _24.z = 1.0;
    vec3 _57 = _24.xyz * _17._m1;
    _24 = vec4(_57.x, _57.y, _57.z, _24.w);   // 缩放 pos
    _27 = dot(_20, _20);   // dot(uv, uv)
    _27 = sqrt(_27);   // uvLen
    vec3 _70 = vec3(_27) * _24.xyz;  // uvLen * 缩放pos    // 相当于uv的设置会影响缩放   这里没有太大影响，单纯把菱形面片放大覆盖屏幕
    _24 = vec4(_70.x, _70.y, _70.z, _24.w);   // 
    vec3 _80 = _24.yyy * _17._m0[1u].xyz;
    _25 = vec4(_80.x, _80.y, _80.z, _25.w);
    vec3 _91 = (_17._m0[0u].xyz * _24.xxx) + _25.xyz;
    _24 = vec4(_91.x, _91.y, _24.z, _91.z);
    vec3 _102 = (_17._m0[2u].xyz * _24.zzz) + _24.xyw;
    _24 = vec4(_102.x, _102.y, _102.z, _24.w);
    vec3 _111 = _24.xyz + _17._m0[3u].xyz;
    _24 = vec4(_111.x, _111.y, _111.z, _24.w);
    vec3 _120 = _24.xyz + (-_6._m5);
    _24 = vec4(_120.x, _120.y, _120.z, _24.w);
    _25 = _24.yyyy * _14._m1[1u];
    _25 = (_14._m1[0u] * _24.xxxx) + _25;
    _24 = (_14._m1[2u] * _24.zzzz) + _25;
    _24 += _14._m1[3u];
    gl_Position = _24;
    _22 = _24;
}

layout(set = 2, binding = 0) uniform sampler2D _24;    // cascadeShadow
layout(set = 2, binding = 1) uniform sampler2D _25;   // depthTexture

layout(location = 0) in vec4 _27;
layout(location = 0) out vec4 _29;

void _57()
{
    _31.x = _27.x;
    _31.y = _27.y * _8._m8.x;
    vec2 _77 = _31.xy / _27.ww;              // screenPos
    _31 = vec4(_77.x, _77.y, _31.z, _31.w);
    vec2 _85 = (_31.xy * vec2(0.5)) + vec2(0.5);    
    _31 = vec4(_85.x, _85.y, _31.z, _31.w); // uv
    _46 = _31.xy * _15._m10.xy;       // uv * texelsize.zw     pixelPos
    _31.x = texture(_25, _31.xy).x;     // depth
    _31.x = (_31.x * 2.0) + (-1.0);    // depth * 2 - 1
    _45 = _46 * vec2(0.00048828125);    // pixelPos / 2048
    bvec2 _120 = greaterThanEqual(_45.xyxx, -_45.xyxx).xy;   // bool2 signMask = (hashSeed >= -hashSeed);
    _36 = bvec4(_120.x, _120.y, _36.z, _36.w);
    _45 = fract(abs(_45));
    vec2 _129 = _45;
    _129.x = _36.x ? _45.x : (-_45.x);
    _129.y = _36.y ? _45.y : (-_45.y);
    _45 = _129;                        // pos   1 / 2048 * 0.474074065685272216796875 = 1 / 4320
    _45 = (_45 * vec2(0.474074065685272216796875)) + vec2(0.25, 0.0);   // 有点像unreal float RandFast( uint2 PixelPos, float Magic = 3571.0 )
    _45 *= _45;
    _45.x = dot(_45, vec2(3571.0));
    _45.x = fract(_45.x);
    _45.x *= _45.x;
    _45.x = dot(_45.xx, vec2(3571.0));
    _45.x = fract(_45.x);          //RandFast
    _45.x += (-0.5);
    _39 = fract(_45.x);  
    _39 *= 6.283185482025146484375;
    _32.x = sin(_39);
    _41.x = cos(_39);          // float2 randDir = float2(cos(angle), sin(angle)); 
    vec2 _207 = _41.xx * vec2(-0.000980000011622905731201171875, 0.000980000011622905731201171875);        // 有点像 1 / 2048 * 2
    _37 = vec4(_207.x, _207.y, _37.z, _37.w);
    vec2 _212 = _32.xx * vec2(-0.000980000011622905731201171875, 0.000980000011622905731201171875);
    _37 = vec4(_37.x, _37.y, _212.x, _212.y);                     // 抖动                  随机抖动
    _45 = _27.xy / _27.ww;
    _32 = _45.yyyy * _15._m5[1u];
    _32 = (_15._m5[0u] * _45.xxxx) + _32;       //抖动偏移采样16次
    _31 = (_15._m5[2u] * _31.xxxx) + _32;
    _31 += _15._m5[3u];
    _47 = 1.0 / _31.w;
    vec3 _254 = vec3(_47) * _31.xyz;           
    _31 = vec4(_254.x, _254.y, _254.z, _31.w);    // 转到世界空间
    _32 = _31.yyyy * _20._m0[1u];
    _32 = (_20._m0[0u] * _31.xxxx) + _32;
    _31 = (_20._m0[2u] * _31.zzzz) + _32;
    _31 += _20._m0[3u];                         // 转到阴影空间
    vec3 _284 = _31.xyz / _31.www;
    _31 = vec4(_284.x, _284.y, _284.z, _31.w);  // shadowCoord
    _32 = _37.xzzy + _31.xyxy;       // shadowCoord + 偏移
    _37 = _37.wxyw + _31.xyxy;
    _41 = textureGather(_24, _32.xy);
    _32 = textureGather(_24, _32.zw);
    _36 = greaterThanEqual(_32, _31.zzzz);
    _32.x = float(_36.x);
    _32.y = float(_36.y);
    _32.z = float(_36.z);
    _32.w = float(_36.w);
    _42 = greaterThanEqual(_41, _31.zzzz);
    _41.x = float(_42.x);
    _41.y = float(_42.y);
    _41.z = float(_42.z);
    _41.w = float(_42.w);
    _31.x = _41.y + _41.x;
    _31.x = _41.z + _31.x;
    _31.x = _41.w + _31.x;
    _45.x = _32.y + _32.x;
    _45.x = _32.z + _45.x;
    _45.x = _32.w + _45.x;
    _31.x = _45.x + _31.x;
    _32 = textureGather(_24, _37.xy);
    _37 = textureGather(_24, _37.zw);
    _40 = greaterThanEqual(_37, _31.zzzz);
    _36 = greaterThanEqual(_32, _31.zzzz);
    _32.x = float(_36.x);
    _32.y = float(_36.y);
    _32.z = float(_36.z);
    _32.w = float(_36.w);
    _37.x = float(_40.x);
    _37.y = float(_40.y);
    _37.z = float(_40.z);
    _37.w = float(_40.w);
    _45.x = _32.y + _32.x;
    _45.x = _32.z + _45.x;
    _45.x = _32.w + _45.x;
    _31.x = _45.x + _31.x;
    _45.x = _37.y + _37.x;
    _45.x = _37.z + _45.x;
    _45.x = _37.w + _45.x;
    _31.x = _45.x + _31.x;
    _29.y = _31.x * 0.0625;          // 1 / 16
    _29 = vec4(vec3(1.0).x, _29.y, vec3(1.0).y, vec3(1.0).z);
}


// 可能有一个ssao 补充的pass  compute shader       unreal的 capsule ao    这里是ambient部分
#version 460
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(set = 2, binding = 0) uniform sampler2D _24;             // depth texture
layout(set = 2, binding = 1) uniform sampler2D _25;             // normal texture encode的
layout(set = 3, binding = 3, rgba32f) uniform writeonly image2D _28; // 结果贴图 x是occlusion  yz是pack depth

shared uint _103[1];
shared uint _104[1];
shared _105 _108[64];
shared uint _109[1];
shared uint _110[1];
shared uint _111[1];
shared uint _112[1];

void main()
{
    uint _1086 = 0u;
    _32 = (gl_LocalInvocationID.y * 8u) + gl_LocalInvocationID.x;                    // index
    uvec2 _141 = gl_GlobalInvocationID.xy * uvec2(_20._m1, _20._m1);      // 获取uv  *2  输出贴图是输入的一半
    _40 = uvec4(_141.x, _141.y, _40.z, _40.w);            
    _40.z = 0u;
    _40.w = 0u;
    _66.x = texelFetch(_24, ivec2(_40.xy), int(_40.w)).x;         // 获取 rawDepth
    _74 = (_6._m10.z * _66.x) + _6._m10.w;             // 线性深度  linear depth
    _74 = 1.0 / _74;
    if (_32 == 0u)              // 初始化share 变量
    {
        _109[0u] = 2139095039u;         //groupMinDepth   float infinity
        _110[0u] = 0u;               // groupMaxDepth = 0
        _111[0u] = 2139095039u;   // groupFarMinDepth = infinity
        _112[0u] = 0u;        // groupNearMaxDepth = 0
        _103[0u] = 0u;
        _104[0u] = 0u;
    }
    barrier();
    _90 = _74 < 200.0;                 // 检查深度是否在有效范围内
    if (_90)
    {
        uint _195 = atomicMin(_109[0u], floatBitsToUint(_74));
        uint _199 = atomicMax(_110[0u], floatBitsToUint(_74));     // 最小 最大
    }
    barrier();
    _45.x = uintBitsToFloat(_109[0u]); // 最小
    _45.y = uintBitsToFloat(_110[0u]); // 最大
    _80 = _45.y + _45.x;
    _80 *= 0.5;      //  float group_mid_depth = (group_max_depth + group_min_depth) * 0.5;
    if (_90)
    {
        _90 = _74 >= _80;
        if (_90)
        {
            uint _228 = atomicMin(_111[0u], floatBitsToUint(_74));  // 更新“远”组的最小深度 groupFarMinDepth
        }
        _90 = _80 >= _74;             // 如果当前像素深度在“近”的一半
        if (_90)
        {
            uint _238 = atomicMax(_112[0u], floatBitsToUint(_74));       // 更新“近”组的最大深度 groupNearMaxDepth
        }
    }
    barrier();
    _89 = uintBitsToFloat(_111[0u]);        // groupFarMinDepth
    _93 = uintBitsToFloat(_112[0u]);        // groupNearMaxDepth
    _50 = equal(floatBitsToInt(_45.xyxx), ivec4(2139095039, 0, 0, 0)).xy;  //  检查工作组内是否所有像素都无效 (例如，整个Tile都是天空)
    _50.x = _50.y && _50.x;
    _71.x = _74 / _20._m4;     // // _20._m4是归一化距离     // 将线性深度编码为两个8位值，存入G和B通道     数据50
    _71.x = clamp(_71.x, 0.0, 1.0);
    _71.x = (_71.x * 65535.0) + 0.5;
    _72 = uint(_71.x);
    _81 = _72 >> 8u;     // 高8位
    _71.y = float(_81);
    _72 &= 255u;         // 低8位
    _71.x = float(_72); 
    vec2 _296 = _71.yx * vec2(0.0039215688593685626983642578125);   // 1 / 255    // 转换回 [0,1] 范围 packed_depth 
    _51 = vec4(_51.x, _296.x, _296.y, _51.w);
    _51.w = 1.0;
    imageStore(_28, ivec2(gl_GlobalInvocationID.xy), _51.wyzw);    // 存入pack depth
    if (!_50.x)           // 这个tile的数据有效
    {
        vec2 _313 = vec2(_40.xy);       // screenpos        --- 步骤 1: 计算Tile四个角在视图空间中的射线方向 ---
        _47 = vec4(_313.x, _313.y, _47.z, _47.w);
        vec2 _319 = _47.xy + vec2(0.5);
        _47 = vec4(_319.x, _319.y, _47.z, _47.w);
        vec2 _328 = _47.xy * _20._m10.zw;          // uv
        _47 = vec4(_328.x, _328.y, _47.z, _47.w);
        _47.z = _47.y * _6._m8.x;
        _52.x = -1.0;
        _52.y = -_6._m8.x;
        vec2 _350 = (_47.xz * vec2(2.0)) + _52.xy;  
        _47 = vec4(_350.x, _350.y, _47.z, _47.w);      // uv * 2 - 1
        _66.x = (_66.x * 2.0) + (-1.0);              // rawDepth * 2 - 1
        _52 = _47.yyyy * _14._m5[1u];
        _47 = (_14._m5[0u] * _47.xxxx) + _52;
        _47 = (_14._m5[2u] * _66.xxxx) + _47;
        _47 += _14._m5[3u];                                 // worldPos
        _66.x = 1.0 / _47.w;
        vec3 _394 = (_47.xyz * _66.xxx) + _6._m5;           // worldPos + cameraPos
        _47 = vec4(_394.x, _394.y, _394.z, _47.w);          // worldPos
        _52 = vec4(_14._m7[0u].xx.x, _52.y, _14._m7[0u].xx.y, _52.w); //可能等于 1.0 / ProjMat[0][0] 
        _52.y = _14._m7[1u].y;        // 可能等于 1.0 / ProjMat[1][1]
        vec2 _410 = _52.xy * vec2(2.0, -2.0);
        _52 = vec4(_410.x, _410.y, _52.z, _52.w);
        vec2 _418 = _52.xy / _20._m3;            // (450, 800) / 8    会结合到下面计算
        _52 = vec4(_418.x, _418.y, _52.z, _52.w);
        _52.w = -_14._m7[1u].y;
        vec2 _428 = vec2(gl_WorkGroupID.xy);     
        _55 = vec4(_428.x, _428.y, _55.z, _55.w);       // group id  tile_coord_min 
        vec2 _439 = (_55.xy * _52.xy) + (-_52.zw);       // (450, 800) / 8    相当于根据这个算出了单个tile左下角的位置 （屏幕到view空间）
        _55 = vec4(_439.x, _439.y, _55.z, _55.w);
        vec2 _445 = _55.xy * vec2(1.0, -1.0);             
        _55 = vec4(_445.x, _445.y, _55.z, _55.w);     // topLeft_ray_dir
        _87 = gl_WorkGroupID.xy + uvec2(1u);    // tile_coord_max 
        _84 = vec2(_87);
        vec2 _461 = (_84 * _52.xy) + (-_52.zw);       // (450, 800) / 8    相当于根据这个算出了 当前tile的范围在viewspace
        _52 = vec4(_461.x, _461.y, _52.z, _52.w);
        vec2 _466 = _52.xy * vec2(1.0, -1.0);
        _52 = vec4(_466.x, _466.y, _52.z, _52.w);   // bottomRight_ray_dir
        _82 = _45.xx * _55.xy;           // --- 步骤 2: 构建第一个包围盒 (近处物体) ---          //vec2 corner_a = group_min_depth * topLeft_ray_dir.xy;
        _84 = vec2(_93) * _55.xy;                       // vec2 corner_b = group_near_max_depth * topLeft_ray_dir.xy;
        vec2 _481 = min(_82, _84);
        _56 = vec4(_481.x, _481.y, _56.z, _56.w);
        _82 = _45.xx * _52.xy;              //vec2 corner_c = group_min_depth * bottomRight_ray_dir.xy;
        _84 = vec2(_93) * _52.xy;           // vec2 corner_d = group_near_max_depth * bottomRight_ray_dir.xy;
        vec2 _496 = max(_82, _84);            // 找到这四个角点在XY平面上形成的AABB (轴对齐包围盒)
        _57 = vec3(_496.x, _496.y, _57.z);
        _56.z = -_45.x;             // -group_min_depth;
        _57.z = -_93;                       //  -group_near_max_depth;        分别平面的深度
        vec2 _510 = vec2(_89) * _55.xy;                       //   步骤 3: 构建第二个包围盒 (远处物体) ---
        _45 = vec4(_510.x, _45.y, _45.z, _510.y); // corner_a = group_far_min_depth * topLeft_ray_dir.xy;
        _82 = _45.yy * _55.xy;                      // corner_b = group_max_depth * topLeft_ray_dir.xy;
        vec2 _521 = min(_45.xw, _82);
        _55 = vec4(_521.x, _521.y, _55.z, _55.w);  // 
        vec2 _528 = vec2(_89) * _52.xy;         // corner_c = group_far_min_depth * bottomRight_ray_dir.xy;
        _45 = vec4(_528.x, _45.y, _45.z, _528.y);   
        vec2 _535 = _45.yy * _52.xy;            //corner_d = group_max_depth * bottomRight_ray_dir.xy;
        _52 = vec4(_535.x, _535.y, _52.z, _52.w);
        vec2 _542 = max(_45.xw, _52.xy);
        _52 = vec4(_542.x, _542.y, _52.z, _52.w);
        _55.z = -_89;                   // -group_far_min_depth;
        _52.z = -_45.y;                 // -group_max_depth;
        vec3 _555 = _56.xyz + _57;      // // --- 步骤 4: 将两个视图空间的AABB转换为世界空间的包围体 (可能是OBB或包围球) ---
        _45 = vec4(_555.x, _555.y, _45.z, _555.z); 
        vec3 _561 = _45.xyw * vec3(0.5);     
        _56 = vec4(_561.x, _561.y, _561.z, _56.w);   // vec3 near_box_center = (near_box_min_corner.xyz + near_box_max_corner) * 0.5;
        _59 = _56.yyy * _14._m6[1u].xyz;
        vec3 _577 = (_14._m6[0u].xyz * _56.xxx) + _59;
        _56 = vec4(_577.x, _577.y, _56.z, _577.z);
        vec3 _588 = (_14._m6[2u].xyz * _56.zzz) + _56.xyw;
        _56 = vec4(_588.x, _588.y, _588.z, _56.w);
        vec3 _596 = _56.xyz + _14._m6[3u].xyz;
        _56 = vec4(_596.x, _596.y, _596.z, _56.w);
        vec3 _603 = _56.xyz + _6._m5;     
        _56 = vec4(_603.x, _603.y, _603.z, _56.w); // near_box_center  使用逆视图矩阵(_14._m6)将中心点变换到世界空间_6._m5 可能是相机位置的额外偏移
        vec3 _611 = (_45.xyw * vec3(0.5)) + (-_57);      
        _45 = vec4(_611.x, _611.y, _45.z, _611.z);          // box 范围的 extent
        _66.x = dot(_45.xyw, _45.xyw); //float near_bounding_sphere_radius_sq = dot(near_box_extents, near_box_extents);计算包围球的半径平方，用于快速剔除
        vec3 _624 = _52.xyz + _55.xyz;        //far_box_center 
        _45 = vec4(_624.x, _624.y, _45.z, _624.z);
        vec3 _629 = _45.xyw * vec3(0.5);
        _55 = vec4(_629.x, _629.y, _629.z, _55.w);
        _57 = _55.yyy * _14._m6[1u].xyz;
        vec3 _645 = (_14._m6[0u].xyz * _55.xxx) + _57;
        _55 = vec4(_645.x, _645.y, _55.z, _645.z);
        vec3 _656 = (_14._m6[2u].xyz * _55.zzz) + _55.xyw;
        _55 = vec4(_656.x, _656.y, _656.z, _55.w);
        vec3 _664 = _55.xyz + _14._m6[3u].xyz;
        _55 = vec4(_664.x, _664.y, _664.z, _55.w);  
        vec3 _671 = _55.xyz + _6._m5;          
        _55 = vec4(_671.x, _671.y, _671.z, _55.w);       //far_box_center   world_far_box_center 将中心点变换到世界空间
        vec3 _680 = (_45.xyw * vec3(0.5)) + (-_52.xyz);
        _45 = vec4(_680.x, _680.y, _45.z, _680.z);
        _66.z = dot(_45.xyw, _45.xyw);        // float far_bounding_sphere_radius_sq = dot(far_box_extents, far_box_extents); // 原 _66.z
        vec2 _691 = sqrt(_66.xz);         
        _66 = vec3(_691.x, _66.y, _691.y); //vec2 sphere_radii = sqrt(vec2(near_bounding_sphere_radius_sq, far_bounding_sphere_radius_sq)); // 原 _66.xz
        _76 = _74 >= _80;       // 远处      
        _34 = texelFetch(_25, ivec2(_40.xy), int(_40.w)).xyz;    // normalTex
        _60 = (_34 * vec3(2.0)) + vec3(-1.0);          // decode normal
        _37 = int((0.0 < _60.z) ? 4294967295u : 0u);
        _69 = int((_60.z < 0.0) ? 4294967295u : 0u);
        _37 = (-_37) + _69;
        _88 = float(_37);
        _99 = dot(_60.xy, _60.xy);
        _62 = vec2(_99) + vec2(1.0, -1.0);
        vec2 _741 = _60.xy + _60.xy;
        _60 = vec3(_741.x, _741.y, _60.z);
        vec2 _748 = _60.xy / _62.xx;
        _63 = vec3(_748.x, _748.y, _63.z);
        _60.x = _62.y / _62.x;
        _63.z = (-_88) * _60.x;          // decode normal   normal        
        _34.y = 0.0;
        _45.x = 0.0;
        for (uint _767 = _32; _767 < _20._m0; _767 += 64u)    //  _32是当前线程index   ， 每个index处理一个数据
        {
            _94 = int(_767) << 1;         //ShadowCapsuleShapes的长度为两倍胶囊体数量，偶数索引的值表示中心和半径，奇数索引的值表示方向和长度
            _97 = bitfieldInsert(1, int(_767), 1, 31);       // _97 = probe_index * 2 + 1 (奇数索引，用于访问方向数据)
            _54 = abs(_20._m5[_97].y) < abs(_20._m5[_97].x);      //  
            _73.x = dot(_20._m5[_97].xz, _20._m5[_97].xz);   // 某个方向 cone_axis   生成第一个正交向量 (Tangent) ---找到一个与 cone_axis 垂直的向量。
            _73.x = sqrt(_73.x);                                        // _20._m5[_97] 锥体方向 w是轴长
            _73.x = 1.0 / _73.x;
            _34.x = _73.x * (-_20._m5[_97].z);
            _34.z = _73.x * _20._m5[_97].x;                  // xz 方向       
            _73.x = dot(_20._m5[_97].yz, _20._m5[_97].yz);
            _73.x = sqrt(_73.x);
            _73.x = 1.0 / _73.x;
            _45.y = _73.x * _20._m5[_97].z;
            _45.z = _73.x * (-_20._m5[_97].y);         // yz方向
            vec3 _866 = mix(_45.xyz, _34, bvec3(_54));    // 选择大的方向 someDir
            _52 = vec4(_866.x, _866.y, _866.z, _52.w);
            _57 = _52.yzx * _20._m5[_97].zxy;
            _57 = (_20._m5[_97].yzx * _52.zxy) + (-_57);          // corss  someDir 
            _34.x = (_20._m5[_97].w * 0.5) + _20._m5[_94].w;  // (cone_angle_param * 0.5 + radius)   _20._m5[_94].xyz 中心 _20._m5[_94].w 半径
            _34.x = _20._m5[_94].w / _34.x;
            _59 = _34.xxx * _20._m5[_97].xyz;         // 这是 cone_axis 的一个缩放版本   主要是轴体的对距离的影响   像是椭球体的occlusion probe
            _64 = _56.xyz + (-_20._m5[_94].xyz);    // near_box_center - probecenter
            _65.x = dot(_64, _52.xyz);
            _65.y = dot(_64, _57);
            _65.z = dot(_64, _59);         // 变换到局部坐标near_box_center          neardist
            _64 = _55.xyz + (-_20._m5[_94].xyz);     // far_box_center  - probecenter
            _52.x = dot(_64, _52.xyz);
            _52.y = dot(_64, _57);
            _52.z = dot(_64, _59);       // 变换到局部坐标far_box_center  fardist
            _34.x = _20._m2 + _20._m5[_94].w;    // 半径加上一个可以允许的误差范围 _20._m2
            _77 = _66.x + _34.x;       // near_bounding_sphere_radius_sq + _34.x
            _70 = dot(-_65, -_65);        // neardist dot sqr
            _77 *= _77;    // lensqr 
            _79 = _70 < _77;
            if (_79)        //probe  在范围之内          
            {
                uint _978 = atomicAdd(_103[0u], 1u);
                _58 = _978;
                _78 = min(_58, 31u);
                _108[_78]._m0[0u] = _767;       // 记录probe 的index到一个数组
            } 
            _34.x = _66.z + _34.x;      // far_bounding_sphere_radius_sq + _34.x  范围是两个半径的和
            _77 = dot(-_52.xyz, -_52.xyz);     // 局部fardist dot sqr
            _34.x *= _34.x;   
            _43 = _77 < _34.x;    // probe 在范围之内
            if (_43)
            {
                uint _1012 = atomicAdd(_104[0u], 1u);
                _53 = _1012;
                _40.x = min(_53, 31u);
                _37 = int(_40.x) + 32;
                _108[_37]._m0[0u] = _767;  // 记录probe 的index到一个数组
            }
        }
        barrier();    // 记录完当前tile包含的probe index
        _32 = _103[0u];        //  near组
        _67 = _104[0u];        // far组
        _32 = _76 ? _67 : _32;    // uint probe_count = is_pixel_far ? _104[0u] : _103[0u];
        _32 = min(_32, 32u);           // 最多处理32个探针
        _66.x = 1.0 / _20._m2;          // 
        _89 = cos(_20._m9);           // 
        _89 = ((-_89) * 6.283185482025146484375) + 6.283185482025146484375;            //一个预计算的归一化常数
        _75 = _76 ? 32 : 0;          // uint list_offset = is_pixel_far ? 32u : 0u;
        _34.x = (-_63.y) + (-_20._m6.x);          // -normal.y - _20._m6.x
        _34.x = dot(_20._m6.yy, _34.xx);       // 缩放
        _34.x = clamp(_34.x, 0.0, 1.0);
        _34.x = (_20._m8 * (-_34.x)) + 1.0;
        _34.x = max(_34.x, 0.00999999977648258209228515625);  // 法线y相关因子
        _45.y = 0.0;
        _52.x = 0.0;
        _68 = 1.0;
        for (; _1086 < _32; _1086++)        // 遍历probe           unreal ShadowConeTraceAgainstCulledCapsuleShapes
        {
            _92 = _75 + int(_1086);              // index
            _92 = int(_108[_92]._m0[0u]);         // uint probe_index 
            _94 = _92 << 1;                             //  _94 = probe_index * 2 (偶数索引，指向位置和半径)
            _96 = _34.x * _20._m5[_94].w;                // probe 半径
            _92 = bitfieldInsert(1, _92, 1, 31);       //  _92 = probe_index * 2 + 1 (奇数索引，指向方向和锥角)
            _98 = abs(_20._m5[_92].y) < abs(_20._m5[_92].x);   // 选择大的方向 someDir
            _55.x = dot(_20._m5[_92].xz, _20._m5[_92].xz);
            _55.x = sqrt(_55.x);
            _55.x = 1.0 / _55.x;
            _45.x = _55.x * (-_20._m5[_92].z);
            _45.z = _55.x * _20._m5[_92].x;
            _55.x = dot(_20._m5[_92].yz, _20._m5[_92].yz);
            _55.x = sqrt(_55.x);
            _55.x = 1.0 / _55.x;
            _52.y = _55.x * _20._m5[_92].z;
            _52.z = _55.x * (-_20._m5[_92].y);
            _73 = mix(_52.xyz, _45.xyz, bvec3(_98));    // 选择大的方向 someDir   与上面类似
            vec3 _1201 = _73.yzx * _20._m5[_92].zxy;
            _55 = vec4(_1201.x, _1201.y, _1201.z, _55.w);
            vec3 _1214 = (_20._m5[_92].yzx * _73.zxy) + (-_55.xyz);
            _55 = vec4(_1214.x, _1214.y, _1214.z, _55.w);
            _45.x = (_20._m5[_92].w * 0.5) + _96;
            _45.x = _96 / _45.x;
            vec3 _1235 = _45.xxx * _20._m5[_92].xyz;       
            _56 = vec4(_1235.x, _1235.y, _1235.z, _56.w);    // 与上面类似
            vec3 _1245 = _47.xyz + (-_20._m5[_94].xyz);    // 像素 worldPos - probecenter   当前像素位置的距离方向
            _45 = vec4(_1245.x, _45.y, _1245.y, _1245.z); //  当前像素位置的距离方向
            _57.x = dot(_45.xzw, _73);
            _57.y = dot(_45.xzw, _55.xyz);
            _57.z = dot(_45.xzw, _56.xyz);     // 位置方向转到probe 本地坐标
            _59.x = dot(_63, _73);
            _59.y = dot(_63, _55.xyz);
            _59.z = dot(_63, _56.xyz);   // normal 转到probe 本地坐标
            _91 = dot(_57, _57);
            _91 = sqrt(_91);
            vec3 _1288 = (-_57) / vec3(_91);           
            _45 = vec4(_1288.x, _45.y, _1288.y, _1288.z); // 位置方向归一化
            _73.x = dot(_59, _59);
            _73.x = inversesqrt(_73.x);
            _73 = _73.xxx * _59;         // normal归一化
            _45.x = dot(_45.xzw, _73);     // 计算位置和法线的cos
            _80 = (abs(_45.x) * (-0.15658299624919891357421875)) + 1.57079637050628662109375;    // acos(x) bengin
            _93 = (-abs(_45.x)) + 1.0; //见https://seblagarde.wordpress.com/2014/12/01/inverse-trigonometric-functions-gpu-optimization-for-amd-gcn-architecture/
            _93 = sqrt(_93);       // _93 = sqrt(1 - |x|)
            _73.x = _93 * _80;    // _73.x = sqrt(1 - |x|) * ((PI/2) - a*|x|)
            _46 = _45.x >= 0.0;
            _80 = ((-_80) * _93) + 3.1415927410125732421875;
            _45.x = _46 ? _73.x : _80;       // acos(x) end         // 位置法线夹角
            _80 = _96 / _91;             // // _80 = y = effective_radius / dist_to_probe
            _95 = _80 < 1.0;               // ATan(x) bengin
            _96 = 1.0 / _80;
            _80 = _95 ? _80 : _96;
            _96 = _80 * _80;
            _73.x = (_96 * 0.087292902171611785888671875) + (-0.3018949925899505615234375);
            _96 = (_73.x * _96) + 1.0;
            _73.x = _80 * _96;
            _80 = ((-_96) * _80) + 1.57079637050628662109375;
            _80 = _95 ? _73.x : _80;        //  ATan(x) end  probe 对 位置展开的夹角 // 至此, _80 = horizon_angle, 即探针球体在像素处张开的半角。
            _93 = max(_80, _20._m9);        // upper_bound
            _96 = min(_80, _20._m9);        // lower_bound
            _93 += (-_96);           // angular_difference = upper_bound - lower_bound
            _95 = _93 >= _45.x;   //判断 pixel_angle 是否完全在遮蔽区或完全在非遮蔽区       展开的夹角没有包含到位置和法线夹角       
            _96 = cos(_96);     //  cos(lower_bound_angle)
            _96 = ((-_96) * 6.283185482025146484375) + 6.283185482025146484375;      // 预计算一个完全遮蔽时的值
            _73.x = _80 + _20._m9;     // sum_of_angles = horizon_angle + cone_angle
            _83 = _45.x >= _73.x;     // is_fully_lit = pixel_angle >= sum_of_angles
            _80 = (-_80) + _20._m9;      // diff_of_angles = cone_angle - horizon_angle
            _45.x = (-abs(_80)) + _45.x;
            _80 = (-abs(_80)) + _73.x;
            _45.x /= _80;       
            _45.x = clamp(_45.x, 0.0, 1.0);      // blend_factor = (pixel_angle - |diff_of_angles|) / (sum_of_angles - |diff_of_angles|)
            _45.x = (-_45.x) + 1.0;     //  smoothstep(t)
            _80 = (_45.x * (-2.0)) + 3.0;
            _45.x *= _45.x;
            _45.x *= _80;     //  smoothstep(t)  blend_factor
            _45.x = _96 * _45.x;       //  将平滑因子乘以完全遮蔽时的值  过渡值
            _45.x = _83 ? 0.0 : _45.x;     // // 如果在亮区，遮蔽为0
            _45.x = _95 ? _96 : _45.x;   // / 如果在完全遮蔽，直接使用完全遮蔽值
            _45.x /= _89;      // 
            _45.x = min(_45.x, 1.0);   // 归一化
            _45.x = (-_45.x) + 1.0;     // occlusion = 1.0 - visibility
            _91 = _66.x * _91;     // // _91 = dist_to_probe / safety_margin
            _91 = (_91 * 3.0) + (-2.0);
            _91 = clamp(_91, 0.0, 1.0);    // 自定义的距离衰减曲线  saturate(_91 * 3.0 + -2.0)
            _80 = (-_45.x) + 1.0;  
            _91 = (_91 * _80) + _45.x;  //  lerp(occlusion, 1, _91)
            _68 = _91 * _68;      // 累乘 finalOcclusion *= finalOcclusion
        }
        _30 = log2(_68);
        _30 *= _20._m7;
        _51.x = exp2(_30);      //  pow(finalOcclusion, _20._m7);  调整一下曲线
        imageStore(_28, ivec2(gl_GlobalInvocationID.xy), _51);   // 存入occlusion
    }
}


// 合并 capsule AO 的结果到 a通道的 AO    只是写入a通道   blend One One  blendop  minimum  // 自定义四次采样的混合
layout(set = 2, binding = 0) uniform sampler2D _19;       // AOTexture  x ao  yz packdepth
layout(set = 2, binding = 1) uniform sampler2D _20;     // depth_texture

layout(location = 0) in vec2 _23;
layout(location = 0) out vec4 _25;

void _66()
{
    _27 = textureLod(_20, _23, 0.0).x;             // / --- 步骤 1: 获取当前像素的线性深度 ---
    _27 = (_8._m10.z * _27)  + _8._m10.w;
    _27 = 1.0 / _27;                           //linear_depth 
    _38 = _15._m10.x * 0.5;
    _38 = floor(_38);         // width
    _49 = (_23 * vec2(_38)) + vec2(-0.5);
    _49 = floor(_49);
    _30.y = 1.0 / _38;
    _50.x = _30.y * 0.5;          // 
    _49 = (_49 * _30.yy) + _50.xx;   //    vec2 uv_p00 = (capsule_ao_pixel_coord * vec2(inv_tex_half_width)) + vec2(half_pixel_uv); // _49
    _50 = _30.yy + _49;                 //uv +  texelsize.xx           ++
    _33 = textureLod(_19, _50, 0.0).xyz;     //   AOTexture
    _36 = _33.yz * vec2(255.0);
    _52 = uvec2(_36);
    _51 = int(_52.x) << 8;
    _52.x = _52.y + uint(_51);
    _50.x = float(_52.x);    // 
    _50.x *= _8._m8.z;      // 50   
    _34.w = _50.x * 1.525902189314365386962890625e-05;    // 1 / 65535          // decode pixel depth
    _30.x = 0.0;
    _30 = _30.yxxy + _49.xyxy;                          // +0    0+
    _47 = textureLod(_19, _30.xy, 0.0).xyz;      // +0
    _32 = textureLod(_19, _30.zw, 0.0).xyz;      // +0    0+
    _37 = _47.yz * vec2(255.0);
    _53 = uvec2(_37);
    _55 = int(_53.x) << 8;
    _57 = _53.y + uint(_55);
    _54 = float(_57);
    _39.z = _54 * _8._m8.z;
    _37 = _32.yz * vec2(255.0);
    _46 = uvec2(_37);
    _43 = int(_46.x) << 8;
    _46.x = _46.y + uint(_43);
    _39.x = float(_46.x);
    _39.x *= _8._m8.z;
    vec2 _226 = _39.zx * vec2(1.525902189314365386962890625e-05);          // pixel depth
    _34 = vec4(_34.x, _226.x, _226.y, _34.w);     // pixel depth
    _40 = textureLod(_19, _49, 0.0).xyz;        // 00
    _49 = (-_49) + _23;     // uvdiff1 
    _37 = _40.yz * vec2(255.0);
    _52 = uvec2(_37);
    _51 = int(_52.x) << 8;
    _52.x = _52.y + uint(_51);
    _50.x = float(_52.x);
    _50.x *= _8._m8.z;
    _34.x = _50.x * 1.525902189314365386962890625e-05;      // pixel depth
    _34 = (-vec4(_27)) + abs(_34);        // pixel depths - linear_depth        diffDepth
    _34 = abs(_34) + vec4(9.9999997473787516355514526367188e-05);   //+= vec4(1.0e-4);
    _34 = vec4(1.0) / _34;          // 1 / diffDepth        depth_weights 
    _50 = vec2(_38) * _49;             // fractional_part         计算标准的双线性插值权重
    _37 = ((-_49.yx) * vec2(_38)) + vec2(1.0);
    vec2 _294 = _50 * _37;       
    _29 = vec4(_29.x, _294.x, _294.y, _29.w); // bilinear_weights.x = (1.0 - w_x) * (1.0 - w_y);  w_x * (1.0 - w_y);    ...
    _29.w = _50.x * _50.y;
    _29.x = _37.y * _37.x;        // 
    _29 = _34 * _29;         // depth_weights * bilinear_weights
    _37.x = _47.x * _29.y;
    _37.x = (_29.x * _40.x) + _37.x;
    _37.x = (_29.z * _32.x) + _37.x;
    _37.x = (_29.w * _33.x) + _37.x;        // interpolated_ao 
    _48 = dot(_29, vec4(1.0));    //total_weight 
    _37.x /= _48;       //  interpolated_ao /= total_weight;
    _25.w = _37.x;
    _25 = vec4(vec3(0.0).x, vec3(0.0).y, vec3(0.0).z, _25.w);        // 输出AO
}


// skin pass  // 写入皮肤的 diffuse only buffer   和  profile 
layout(location = 0) in vec4 _19;       // positionOS
layout(location = 1) in vec3 _21;       // normalOS   
layout(location = 2) in vec4 _22;       // tangentOS
layout(location = 3) in vec2 _25;       // texcoord0
layout(location = 4) in vec2 _26;       // texcoord1
layout(location = 0) out vec4 _28;      // uvs  打包的UV坐标
layout(location = 5) out vec3 _30;      // positionWS
layout(location = 1) out vec4 _31;      // normalWS (w分量 存入viewDir)
layout(location = 2) out vec4 _32;      // tangentWS
layout(location = 3) out vec4 _33;      // binormalWS 
layout(location = 4) out vec4 _34;      // positionCS

void main()
{
    _36 = _19.yyy * _12._m0[1u].xyz;
    _36 = (_12._m0[0u].xyz * _19.xxx) + _36;
    _36 = (_12._m0[2u].xyz * _19.zzz) + _36;
    _36 += _12._m0[3u].xyz;                // positionWS
    vec3 _100 = _36 + (-_6._m5);        //  positionRWS              
    _38 = vec4(_100.x, _100.y, _100.z, _38.w);
    _39 = _38.yyyy * _17._m1[1u];
    _39 = (_17._m1[0u] * _38.xxxx) + _39;
    _38 = (_17._m1[2u] * _38.zzzz) + _39;
    _38 += _17._m1[3u];                       // positionCS
    float _128 = abs(_38.w);
    float _130 = -_128;
    float _132 = _130 * 0.0063999998383224010467529296875; // -abs(positionCS.w) * 0.0064   zOffset
    float _135 = _132 + _38.z;            // positionCS.z + zOffset
    gl_Position.z = _135;
    gl_Position = vec4(_38.xyw.x, _38.xyw.y, gl_Position.z, _38.xyw.z);          // positionCS
    _34 = _38;                                  // positionCS   没有偏移
    _38 = vec4(_25.x, _25.y, _38.z, _38.w);     // texcoord0
    _38 = vec4(_38.x, _38.y, _26.x, _26.y);     // texcoord1
    _28 = _38;                              // uvs
    _30 = _36;                          // positionWS
    _36 = (-_36) + _6._m6;              // cameraPos - positionWS   viewDirWS
    _31.w = _36.x;                      // 
    _40.x = dot(_21, _12._m1[0u].xyz);
    _40.y = dot(_21, _12._m1[1u].xyz);
    _40.z = dot(_21, _12._m1[2u].xyz);    // normalWS
    _44 = dot(_40, _40);
    _44 = inversesqrt(_44);
    _40 = vec3(_44) * _40;
    _31 = vec4(_40.x, _40.y, _40.z, _31.w);     // normalWS  w是viewDirWS.x
    _32.w = _36.y;
    _33.w = _36.z;
    _36.x = _12._m0[0u].x;
    _36.y = _12._m0[1u].x;
    _36.z = _12._m0[2u].x;
    _41.x = dot(_36, _22.xyz);
    _36.x = _12._m0[0u].y;
    _36.y = _12._m0[1u].y;
    _36.z = _12._m0[2u].y;
    _41.y = dot(_36, _22.xyz);
    _36.x = _12._m0[0u].z;
    _36.y = _12._m0[1u].z;
    _36.z = _12._m0[2u].z;
    _41.z = dot(_36, _22.xyz);   // tangentWS
    _44 = dot(_41, _41);
    _44 = inversesqrt(_44);
    _41 = vec3(_44) * _41;
    _32 = vec4(_41.x, _41.y, _41.z, _32.w);     // tangentWS
    _42 = _40.zxy * _41.yzx;
    _40 = (_40.yzx * _41.zxy) + (-_42);         // cross(normalWS, tangentWS)  binormalWS
    _44 = _22.w * _12._m3.w;            // tangentOS.w * unity_WorldTransformParams.w
    vec3 _273 = vec3(_44) * _40;      // tangentOS.w * unity_WorldTransformParams.w * binormalWS
    _33 = vec4(_273.x, _273.y, _273.z, _33.w);   // binormalWS
}   

layout(set = 2, binding = 0) uniform sampler2D _33;     // tileLightIndexTexture
layout(set = 2, binding = 1) uniform sampler2D _34;     // paramTexture
layout(set = 2, binding = 2) uniform sampler2D _35;     // normalTexture
layout(set = 2, binding = 3) uniform sampler2D _36;     // shdowAndAOTexture

layout(location = 0) in vec4 _38;       // uvs  打包的UV坐标
layout(location = 5) in vec3 _40;       // positionWS
layout(location = 1) in vec4 _41;       // normalWS (w分量 存入viewDir)
layout(location = 2) in vec4 _42;       // tangentWS
layout(location = 3) in vec4 _43;       // binormalWS 
layout(location = 4) in vec4 _44;       // positionCS
layout(location = 0) out vec4 _46;       //  diffuse-only buffer
layout(location = 1) out float _48;    //  alpha 或 profile index，表示皮肤、蜡、叶子等不同散射半径

vec3 _1165 = vec3(255.0);
uint _1204;
vec3 _1206 = vec3(255.0);

void _85()
{
    _50 = texture(_34, _38.xy).y;        //  可能profile index
    _72 = _38.x >= 0.5;
    _74 = float(_72);          // uv.x > 0.5    isRight
    _52.x = _72 ? 0.0 : _24._m14;  
    _52.x = (_24._m13 * _74) + _52.x;   // (isRight ? 0 : _24._m14) + _24._m13 * isRight    isSelect   _24._m13 right用哪个   _24._m14 left用哪个
    _53 = texture(_35, _38.xy, _14._m7);       // normalTex
    _53 = (_53 * vec4(2.0)) + vec4(-1.0);      // normalTex * 2 - 1
    _73.x = dot(_53.xy, _53.xy);
    _73.x = min(_73.x, 1.0);
    _73.x = (-_73.x) + 1.0;
    _54.z = sqrt(_73.x);          // normalZ
    _73.x = dot(_53.zw, _53.zw);
    _73.x = min(_73.x, 1.0);
    _73.x = (-_73.x) + 1.0;
    _56.z = sqrt(_73.x);        // normalZ1
    _54 = vec4(_53.xy.x, _53.xy.y, _54.z, _54.w);        // normal1
    _56 = vec4(_53.zw.x, _53.zw.y, _56.z, _56.w);        // normal2
    _73 = (-_54.xyz) + _56.xyz;
    vec3 _192 = (_52.xxx * _73) + _54.xyz;
    _52 = vec4(_192.x, _192.y, _192.z, _52.w);      // lerp(normal1, normal2, isSelect)  normalTS
    vec3 _199 = _52.yyy * _43.xyz;
    _54 = vec4(_199.x, _199.y, _199.z, _54.w);
    vec3 _209 = (_52.xxx * _42.xyz) + _54.xyz;
    _52 = vec4(_209.x, _209.y, _52.z, _209.z);
    vec3 _219 = (_52.zzz * _41.xyz) + _52.xyw;
    _52 = vec4(_219.x, _219.y, _219.z, _52.w);       // normalWS
    _76 = dot(_52.xyz, _52.xyz);
    _76 = inversesqrt(_76);
    vec3 _233 = vec3(_76) * _52.xyz;
    _52 = vec4(_233.x, _233.y, _233.z, _52.w);      // normalWS
    _52.w = 1.0;                            // SampleSH9
    _54.x = dot(_29._m0[0u], _52);         // 
    _54.y = dot(_29._m0[1u], _52);
    _54.z = dot(_29._m0[2u], _52);
    _53 = _52.yzzx * _52.xyzz;
    _56.x = dot(_29._m0[3u], _53);
    _56.y = dot(_29._m0[4u], _53);
    _56.z = dot(_29._m0[5u], _53);
    _76 = _52.y * _52.y;
    _76 = (_52.x * _52.x) + (-_76);
    vec3 _293 = _54.xyz + _56.xyz;
    _54 = vec4(_293.x, _293.y, _293.z, _54.w);         
    vec3 _305 = (_29._m0[6u].xyz * vec3(_76)) + _54.xyz;
    _54 = vec4(_305.x, _305.y, _305.z, _54.w);      // SampleSH9  end     bakedGI = SampleSHPixel()
    _58.x = _44.x;
    _58.y = _44.y * _18._m8.x;
    vec2 _322 = _58.xy / _44.ww;        
    _65 = vec3(_322.x, _322.y, _65.z);  
    vec2 _329 = (_65.xy * vec2(0.5)) + vec2(0.5);  //  screenUV
    _65 = vec3(_329.x, _329.y, _65.z);
    _53 = texture(_36, _65.xy);                 // shadow_ao 
    _76 = (-_53.x) + 1.0;                 
    _76 = ((-_76) * _21._m6) + 1.0;            //  lerp(1, shadow_ao.x, _21._m6)   shadow   _21._m6 shdowStrength
    _72 = 0.001000000047497451305389404296875 < _76;   // shadow > 0.001
    _54.w = dot(_52.xyz, _14._m1.xyz);            // dot(normalWS, _14._m1.xyz)         ndotl
    _54 = max(_54, vec4(0.0));                      // max(0, ndotl)
    vec3 _364 = _54.www * _21._m2.xyz;             // ndotl * _LightColor
    _56 = vec4(_364.x, _364.y, _364.z, _56.w);
    vec3 _371 = vec3(_76) * _56.xyz;                    
    _56 = vec4(_371.x, _371.y, _371.z, _56.w);      // ndotl * _LightColor * shadow
    vec3 _378 = _56.xyz * vec3(0.3183098733425140380859375);          // 1 / pi *  ndotl * _LightColor * shadow
    _56 = vec4(_378.x, _378.y, _378.z, _56.w);    // 
    vec3 _387 = mix(vec3(0.0), _56.xyz, bvec3(_72));         // lerp(0, 1 / pi *  ndotl * _LightColor * shadow, shadow > 0.001)
    _56 = vec4(_387.x, _387.y, _387.z, _56.w);   // radiance
    _76 = dot(_52.xyz, _21._m0.xyz);         // ndotSkyLightDir
    _76 = max(_76, 0.0);                    // max(ndotSkyLightDir, 0)
    vec3 _403 = vec3(_76) * _21._m3.xyz;    // ndotSkyLightDir * _SkyColor
    _63 = vec4(_403.x, _403.y, _403.z, _63.w);
    vec3 _408 = _63.xyz * vec3(0.3183098733425140380859375);      //  1/pi * ndotSkyLightDir * _SkyColor
    _63 = vec4(_408.x, _408.y, _408.z, _63.w);       // 
    vec3 _418 = (_63.xyz * _53.www) + _56.xyz;        // 1/pi * ndotSkyLightDir * _SkyColor * shadow_ao.a  + radiance
    _56 = vec4(_418.x, _418.y, _418.z, _56.w);      // lightRadiance
    _65.x = _40.y + (-_21._m4.y);        // positionWS.y - _21._m4.y             heightFactor 计算一个基于高度/位置的颜色调整
    _65.x = max(_65.x, -1.0);
    _65.x = min(_65.x, 1.0);        // min(max(positionWS.y - _21._m4.y, -1), 1)
    _65.x = (_65.x * _21._m7) + 1.0;   // 1 + (heightFactor * _21._m7)       heightFactor
    _58 = _65.xxx * _54.xyz;        // heightFactor * bakedGI       // 高度影响gi
    _76 = dot(_58, vec3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625)); // dot( heightFactor * bakedGI, vec3(0.299, 0.587, 0.114)) 
    vec3 _462 = (_54.xyz * _65.xxx) + _21._m1.xyz;      // heightFactor * bakedGI + _21._m1.xyz      giOffset    bakedGIOff 
    _63 = vec4(_462.x, _462.y, _462.z, _63.w);
    vec3 _467 = clamp(_63.xyz, vec3(0.0), vec3(1.0));       
    _63 = vec4(_467.x, _467.y, _467.z, _63.w);       // saturate(bakedGIH, 0, 1)
    vec3 _480 = ((-_54.xyz) * _65.xxx) + _63.xyz;       
    _54 = vec4(_480.x, _480.y, _480.z, _54.w);
    vec3 _490 = (_21._m1.www * _54.xyz) + _58;
    _54 = vec4(_490.x, _490.y, _490.z, _54.w);          // lerp(heightFactor * bakedGI, bakedGIOff, _21._m1.w)      hAffectBakedGI
    _65 = (-vec3(_76)) + _54.xyz;
    _65 = (_21._m0.www * _65) + vec3(_76);                 // lerp(bakedGIIlluminance, hAffectBakedGI, _21._m0.w)  // bakedGI_R
    vec3 _515 = _65 * vec3(_21._m5, _21._m5, _21._m5);   
    _54 = vec4(_515.x, _515.y, _515.z, _54.w);       // bakedGI_R * _21._m5   强度
    vec3 _525 = (_54.xyz * _53.www) + _56.xyz;   // bakedGI_R * _21._m5 * shadow_ao.a + lightRadiance         // lightRadiance      包含了直接光 sky bakedGI
    _54 = vec4(_525.x, _525.y, _525.z, _54.w);    // lightRadiance
    vec2 _534 = _40.xz + (-_14._m4.xy);      
    _65 = vec3(_534.x, _534.y, _65.z);   // positionWS.xz - 14._m4.xy
    vec2 _542 = _65.xy / _14._m4.zw;    
    _65 = vec3(_542.x, _542.y, _65.z);  // (positionWS.xz - 14._m4.xy) / _14._m4.zw     // 世界坐标转换到tile  uv
    _56 = texture(_33, _65.xy);       // tileLightIndex    rgba
    _55 = (_56 * vec4(255.0)) + vec4(0.5);
    _55 = floor(_55);     // 转换为整数          解码出4个光源的索引     lightIndexs
    _53 = (-_53) + vec4(1.0);       // 1 - shadow_ao
    _62 = lessThan(_55, vec4(30.0));  //  lightIndexs < 30
    if (_62.x)          //分别处理光源
    {
        _70 = uint(_55.x);           // lightIndex0
        _63.x = dot(_53, _9._m6[int(_70)]);         // 相当于获取这个光源的阴影参数， 因为 附加的光源的阴影有可能在 y通道或者g通道
    }
    else
    {
        _63.x = 1.0;
    }
    if (_62.y)
    {
        _70 = uint(_55.y);    // lightIndex1
        _63.y = dot(_53, _9._m6[int(_70)]);
    }
    else
    {
        _63.y = 1.0;
    }
    if (_62.z)
    {
        _70 = uint(_55.z);   //  // lightIndex2
        _63.z = dot(_53, _9._m6[int(_70)]);
    }
    else
    {
        _63.z = 1.0;
    }
    if (_62.w)
    {
        _70 = uint(_55.w);  //  // lightIndex3
        _63.w = dot(_53, _9._m6[int(_70)]);
    }
    else
    {
        _63.w = 1.0;
    }
    _72 = _55.x < 255.0;           // 255的index为没有light
    if (_72)
    {
        _53 = (-_63) + vec4(1.0);        //  获取shadow
        _72 = 0.001000000047497451305389404296875 < _53.x;     // 如果像素几乎完全在阴影中，则跳过光照计算
        if (_72)
        {
            _68 = int(_55.x);                    // light_index 
            _58 = ((-_40) * _9._m0[_68].www) + _9._m0[_68].xyz;       // addLightDir // _addLightPos[0].xyz - positionWS * _addLightPos[0].w     w为方向光的时候为0
            _74 = dot(_58, _58);                        
            _74 = max(_74, 1.1754943508222875079687365372222e-38);             // addLightDirLenSqr
            _75 = inversesqrt(_74);
            _58 = vec3(_75) * _58;                          // normalize(addLightDir)
            _75 = (_74 * _9._m4[_68].x) + 1.0;          //(ax+b)/(cx+1)   b截距  a固定y轴截距控制曲线弯曲   c固定x和y轴截距控制曲线弯曲 自定义光源衰减曲线
            _75 = 1.0 / _75;                                 //  attenuation = 1.0 / (_9._m4[_68].x * addLightDirLenSqr + 1);  
            _74 = (_74 * _9._m4[_68].y) + _9._m4[_68].z;   // _9._m4[_68].y * addLightDirLenSqr +  _9._m4[_68].z
            _74 = clamp(_74, 0.0, 1.0);       // saturate(_9._m4[_68].y * addLightDirLenSqr +  _9._m4[_68].z);       // _9._m4 光源距离衰减
            _74 *= _75;                  // saturate(_9._m4[_68].y * addLightDirLenSqr +  _9._m4[_68].z) / (_9._m4[_68].x * addLightDirLenSqr + 1); DistanceAttenuation
            _75 = dot(_9._m5[_68].xyz, _58);   //  half SdotL = dot(spotDirection, lightDirection);      AngleAttenuation
            _75 = (_75 * _9._m1[_68].x) + _9._m1[_68].y;  
            _75 = clamp(_75, 0.0, 1.0);     // half atten = saturate(SdotL * spotAttenuation.x + spotAttenuation.y);
            _75 *= _75;                 //  atten * atten   AngleAttenuation
            _74 = _75 * _74;            // float attenuation = DistanceAttenuation * AngleAttenuation
            vec3 _724 = _53.xxx * _9._m3[_68].xyz; 
            _63 = vec4(_724.x, _724.y, _724.z, _63.w);    // shadow * addLightColor
            _76 = dot(_52.xyz, _58);    // dot(addLightDir, normalWS)        ndotal
            _76 = max(_76, 0.0);            // max(0, adotal)
            vec3 _735 = _63.xyz * vec3(0.3183098733425140380859375);   // 1/pi * shadow * addLightColor
            _63 = vec4(_735.x, _735.y, _735.z, _63.w);
            vec3 _742 = vec3(_74) * _63.xyz;   
            _63 = vec4(_742.x, _742.y, _742.z, _63.w)        // 1/pi * shadow * addLightColor * attenuation
            vec3 _749 = vec3(_76) * _63.xyz;
            _63 = vec4(_749.x, _749.y, _749.z, _63.w);   // // 1/pi * shadow * addLightColor * attenuation * ndotal            addRadiance
            vec3 _754 = max(_63.xyz, vec3(0.0));      
            _63 = vec4(_754.x, _754.y, _754.z, _63.w);    // max(addRadiance, 0)
        }
        else
        {
            _63.x = 0.0;
            _63.y = 0.0;
            _63.z = 0.0;           // addRadiance
        }
        _72 = _55.y < 255.0;
        if (_72)     // 第二个光源
        {
            _72 = 0.001000000047497451305389404296875 < _53.y;
            if (_72)
            {
                _68 = int(_55.y);
                _58 = ((-_40) * _9._m0[_68].www) + _9._m0[_68].xyz;
                _74 = dot(_58, _58);
                _74 = max(_74, 1.1754943508222875079687365372222e-38);
                _75 = inversesqrt(_74);
                _58 = vec3(_75) * _58;
                _75 = (_74 * _9._m4[_68].x) + 1.0;
                _75 = 1.0 / _75;
                _74 = (_74 * _9._m4[_68].y) + _9._m4[_68].z;
                _74 = clamp(_74, 0.0, 1.0);
                _74 *= _75;        //  光源距离衰减
                _75 = dot(_9._m5[_68].xyz, _58);       // AngleAttenuation
                _75 = (_75 * _9._m1[_68].x) + _9._m1[_68].y;
                _75 = clamp(_75, 0.0, 1.0);
                _75 *= _75; 
                _74 = _75 * _74;     // float attenuation = DistanceAttenuation * AngleAttenuation
                _64 = _53.yyy * _9._m3[_68].xyz;
                _76 = dot(_52.xyz, _58);
                _76 = max(_76, 0.0);
                _64 *= vec3(0.3183098733425140380859375);
                _64 = vec3(_74) * _64;
                _64 = vec3(_76) * _64;
                _64 = max(_64, vec3(0.0));   // addRadiance1
                vec3 _871 = _63.xyz + _64;   
                _63 = vec4(_871.x, _871.y, _871.z, _63.w);   //addRadiance = addRadiance1 + addRadiance
            }
            _72 = _55.z < 255.0;
            if (_72)  // 类似
            {
                _72 = 0.001000000047497451305389404296875 < _53.z;
                if (_72)
                {
                    _68 = int(_55.z);
                    _58 = ((-_40) * _9._m0[_68].www) + _9._m0[_68].xyz;
                    _74 = dot(_58, _58);
                    _74 = max(_74, 1.1754943508222875079687365372222e-38);
                    _75 = inversesqrt(_74);
                    _58 = vec3(_75) * _58;
                    _75 = (_74 * _9._m4[_68].x) + 1.0;
                    _75 = 1.0 / _75;
                    _74 = (_74 * _9._m4[_68].y) + _9._m4[_68].z;
                    _74 = clamp(_74, 0.0, 1.0);
                    _74 *= _75;
                    _75 = dot(_9._m5[_68].xyz, _58);
                    _75 = (_75 * _9._m1[_68].x) + _9._m1[_68].y;
                    _75 = clamp(_75, 0.0, 1.0);
                    _75 *= _75;
                    _74 = _75 * _74;
                    _64 = _53.zzz * _9._m3[_68].xyz;
                    _76 = dot(_52.xyz, _58);
                    _76 = max(_76, 0.0);
                    _64 *= vec3(0.3183098733425140380859375);
                    _64 = vec3(_74) * _64;
                    _64 = vec3(_76) * _64;
                    _64 = max(_64, vec3(0.0));
                    vec3 _985 = _63.xyz + _64;    //addRadiance = addRadiance2 + addRadiance
                    _63 = vec4(_985.x, _985.y, _985.z, _63.w);
                }
                _72 = _55.w < 255.0;
                if (_72)
                {
                    _72 = 0.001000000047497451305389404296875 < _53.w;
                    if (_72)
                    {
                        _68 = int(_55.w);
                        _58 = ((-_40) * _9._m0[_68].www) + _9._m0[_68].xyz;
                        _74 = dot(_58, _58);
                        _74 = max(_74, 1.1754943508222875079687365372222e-38);
                        _75 = inversesqrt(_74);
                        _58 = vec3(_75) * _58;
                        _75 = (_74 * _9._m4[_68].x) + 1.0;
                        _75 = 1.0 / _75;
                        _74 = (_74 * _9._m4[_68].y) + _9._m4[_68].z;
                        _74 = clamp(_74, 0.0, 1.0);
                        _74 *= _75;
                        _75 = dot(_9._m5[_68].xyz, _58);
                        _75 = (_75 * _9._m1[_68].x) + _9._m1[_68].y;
                        _75 = clamp(_75, 0.0, 1.0);
                        _75 *= _75;
                        _74 = _75 * _74;
                        _64 = _53.www * _9._m3[_68].xyz;
                        _52.x = dot(_52.xyz, _58);
                        _52.x = max(_52.x, 0.0);
                        _73 = _64 * vec3(0.3183098733425140380859375);
                        _73 = vec3(_74) * _73;
                        vec3 _1096 = _52.xxx * _73;
                        _52 = vec4(_1096.x, _1096.y, _1096.z, _52.w);
                        vec3 _1101 = max(_52.xyz, vec3(0.0));
                        _52 = vec4(_1101.x, _1101.y, _1101.z, _52.w);
                        vec3 _1108 = _52.xyz + _63.xyz;                         // addRadiance = addRadiance3 + addRadiance
                        _63 = vec4(_1108.x, _1108.y, _1108.z, _63.w);
                    }
                }
            }
        }
    }
    else
    {
        _63.x = 0.0;
        _63.y = 0.0;
        _63.z = 0.0;  //addRadiance 
    }
    vec3 _1118 = _54.xyz + _63.xyz;    // lightRadiance + addRadiance
    _46 = vec4(_1118.x, _1118.y, _1118.z, _46.w);   // finalRadiance     diffuse-only buffer
    _52.x = (-_50) + 1.0;        
    _46.w = _52.x;        //  1 - alpha    
    _48 = _52.x;      // 1 - alpha    
}

// Separable SSS 横向模糊
layout(set = 2, binding = 0) uniform sampler2D _7;          // 线性深度
layout(set = 2, binding = 1) uniform sampler2D _8;          //  diffuse only buffer   
layout(set = 2, binding = 2) uniform sampler2D _9;          // skin profile

layout(location = 0) in vec2 _12;   //uv
layout(location = 0) out vec4 _15;
vec3 _390 = vec3(255.0);

void _64()
{
    int _266 = 1;                             // int kernel_index = 1; 
    vec3 _69 = texture(_8, _12).xyz;          
    _17 = vec4(_69.x, _69.y, _69.z, _17.w);   // vec3 center_color = texture(_8, _12).xyz;
    _21.x = texture(_9, _12).x;       // float center_skin_mask = texture(_9, _12).x; // _21.x
    _17.w = (-_21.x) + 1.0;              // 1.0 - center_skin_mask
    _24 = 0.9900000095367431640625 < _17.w;
    if (_24)      // 优化边缘           // 1.0 - center_skin_mask > 0.99  检查当前像素是否几乎不是皮肤        // 1 不是皮肤
    {
        _27.x = _55._m0.x;                  // texelSize.x
        _27.y = 0.0;           // blur_direction      定义采样方向 (e.g., 水平方向)
        _46 = (-_27) + _12;                        // vec2 left_uv = _12 - blur_direction;
        vec3 _107 = texture(_8, _46).xyz;
        _18 = vec4(_107.x, _107.y, _107.z, _18.w);
        _27 += _12;                     // vec2 right_uv = _12 + blur_direction;
        vec3 _116 = texture(_8, _27).xyz;
        _28 = vec4(_116.x, _116.y, _116.z, _28.w);
        _35 = texture(_9, _46).x;
        _18.w = (-_35) + 1.0;               // vec4 left_sample = vec4(texture(_8, left_uv).xyz, 1.0 - texture(_9, left_uv).x);
        _35 = texture(_9, _27).x;
        _28.w = (-_35) + 1.0;               //vec4 right_sample = vec4(texture(_8, right_uv).xyz, 1.0 - texture(_9, right_uv).x);
        _27.x = _18.w + (-_28.w);         // left_sample.w - left_sample.w
        _36 = int((0.0 < _27.x) ? 4294967295u : 0u);
        _44 = int((_27.x < 0.0) ? 4294967295u : 0u);
        _36 = (-_36) + _44;
        _34 = float(_36);
        _34 = _34;                       // 符号
        _34 = clamp(_34, 0.0, 1.0);
        _25 = (-_18) + _28;
        _18 = (vec4(_34) * _25) + _18;         // lerp(left_sample, right_sample, sign)    edge_color 
        _37.x = _17.w + (-_18.w);              // sign(_17.w - edge_color.w)
        _31 = int((0.0 < _37.x) ? 4294967295u : 0u);
        _43 = int((_37.x < 0.0) ? 4294967295u : 0u);
        _31 = (-_31) + _43;
        _28.x = float(_31);
        _28.x = _28.x;
        _28.x = clamp(_28.x, 0.0, 1.0);
        _18 = (-_17) + _18;
        _18 = (_28.xxxx * _18) + _17;          // lerp(center, edge_color, sing)
        _32 = 0.9900000095367431640625 < _18.w; // _18.w > 0.99
        if (_32)
        {
            _15 = _18;            // 如果不是皮肤直接返回
            return;
        }
        _37 = _18.xyz;     // 如果需要模糊，则用插值后的颜色作为模糊的中心点颜色
        _15.w = _18.w;
    }
    else        // 如果是皮肤，则直接使用原始颜色
    {
        _37 = _17.xyz;
        _15.w = _17.w;
    }
    _50 = _55._m0.x * _55._m1;   // depthStepSize = CameraDepthTexture_TexelSize.x * SSSScale // float blur_radius_uv = _55._m0.x * _55._m1; // _50
    _17.x = texture(_7, _12).x;         //  float center_depth = texture(_7, _12).x; // _17.x //centerDepth = 1.0 / (ZBufferParams.z * Sample(CameraDepthTexture, uv).x + ZBufferParams.w)
    _38.x = 5.6712818145751953125 / _17.x;  //相机 2n / (r - l)  2n / OutDepth / (r - l)
    _38.x = _50 * _38.x;    // depthScale = depthStepSize * (5.67128181 / centerDepth)   // // 相当于单位世界距离占uv大小  
    _38.y = 0.0;          // 相当于uv 随深度的缩放
    _39 = _37 * _55._m2[0u].xyz;       // blurredColor = centerColor * Kernel[0].rgb
    // 类似 unreal If the difference in depth is huge, we weight the sample less or not at all
    _50 *= 1701.384521484375;      // depthRejectScale = depthStepSize * 1701.38452   magic number 像素和深度转换比例后续深度差太大就考虑模糊
    _40 = _39;                   // blurredColor
    for (; _266 < _55._m3; _266++)     // for i = 1 .. SamplerSteps-1:  遍历高斯核
    {
        _47 = (_55._m2[_266].ww * _38) + _12;      //  sampleUv = uv + Kernel[i].ww * offset
        _21 = texture(_8, _47).xyz;  // sampleColor = Sample(SceneAndAlphaTex, sampleUv).rgb
        _45 = texture(_7, _47).x;  //sampleDepth = 1.0 / (ZBufferParams.z * Sample(CameraDepthTexture, sampleUv).x + ZBufferParams.w) 
        _49 = texture(_9, _47).x;
        _48 = (-_49) + 1.0;      // sampleTrans = 1.0 - Sample(SceneAndAlphaTex, sampleUv).a
        _47.x = (-_45) + _17.x;
        _47.x = _50 * abs(_47.x);
        _47.x = clamp(_47.x, 0.0, 1.0);  // depthDiff = clamp(depthRejectScale * abs(sampleDepth - centerDepth), 0, 1)
        _41 = (-_21) + _37;  
        _41 = (_47.xxx * _41) + _21;   // mixedColor = Lerp(sampleColor, centerColor, depthDiff)
        _42 = _37 + (-_41);
        _41 = (vec3(_48) * _42) + _41; //  adjustedColor = Lerp(mixedColor, centerColor, sampleTrans)       // sss的强度
        _40 = (_55._m2[_266].xyz * _41) + _40; // blurredColor += Kernel[i].rgb * adjustedColor
    }
    _15 = vec4(_40.x, _40.y, _40.z, _15.w);  // 返回blur color
}

// Separable SSS 纵向模糊



// face skin
layout(location = 0) in vec4 _19;           // positionOS
layout(location = 1) in vec3 _21;           // normalOS
layout(location = 2) in vec4 _22;           // tangentOS
layout(location = 3) in vec2 _25;           // texcoord0
layout(location = 4) in vec2 _26;           // texcoord1
layout(location = 0) out vec4 _28;          // uvs  打包的UV坐标
layout(location = 5) out vec3 _30;          // positionWS
layout(location = 1) out vec4 _31;          // normalWS (w分量 存入viewDir)
layout(location = 2) out vec4 _32;          // tangentWS
layout(location = 3) out vec4 _33;          // binormalWS 
layout(location = 4) out vec4 _34;          // positionCS
vec3 _36;
vec4 _38;
vec4 _39;
vec3 _40;
vec3 _41;
vec3 _42;
float _44;
vec4 _52;

void main()
{
    _36 = _19.yyy * _12._m0[1u].xyz;
    _36 = (_12._m0[0u].xyz * _19.xxx) + _36;
    _36 = (_12._m0[2u].xyz * _19.zzz) + _36;
    _36 += _12._m0[3u].xyz;         // positionWS
    vec3 _100 = _36 + (-_6._m5);          // positionRWS
    _38 = vec4(_100.x, _100.y, _100.z, _38.w);
    _39 = _38.yyyy * _17._m1[1u];
    _39 = (_17._m1[0u] * _38.xxxx) + _39;
    _38 = (_17._m1[2u] * _38.zzzz) + _39;
    _38 += _17._m1[3u];
    gl_Position = _38;         // positionCS
    _34 = _38;      // positionCS   
    _38 = vec4(_25.x, _25.y, _38.z, _38.w); // texcoord0
    _38 = vec4(_38.x, _38.y, _26.x, _26.y); // texcoord1
    _28 = _38;       // uvs
    _30 = _36;          // positionWS
    _36 = (-_36) + _6._m6;    // cameraPos - positionWS   viewDirWS
    _31.w = _36.x;
    _40.x = dot(_21, _12._m1[0u].xyz);
    _40.y = dot(_21, _12._m1[1u].xyz);
    _40.z = dot(_21, _12._m1[2u].xyz); // normalWS
    _44 = dot(_40, _40);
    _44 = inversesqrt(_44);
    _40 = vec3(_44) * _40;
    _31 = vec4(_40.x, _40.y, _40.z, _31.w);  // normalWS  w是viewDirWS.x
    _32.w = _36.y;
    _33.w = _36.z;
    _36.x = _12._m0[0u].x;
    _36.y = _12._m0[1u].x;
    _36.z = _12._m0[2u].x;
    _41.x = dot(_36, _22.xyz);
    _36.x = _12._m0[0u].y;
    _36.y = _12._m0[1u].y;
    _36.z = _12._m0[2u].y;
    _41.y = dot(_36, _22.xyz);
    _36.x = _12._m0[0u].z;
    _36.y = _12._m0[1u].z;
    _36.z = _12._m0[2u].z;
    _41.z = dot(_36, _22.xyz);      // tangentWS
    _44 = dot(_41, _41);
    _44 = inversesqrt(_44);
    _41 = vec3(_44) * _41;
    _32 = vec4(_41.x, _41.y, _41.z, _32.w); // tangentWS
    _42 = _40.zxy * _41.yzx;
    _40 = (_40.yzx * _41.zxy) + (-_42); // cross(normalWS, tangentWS)  binormalWS
    _44 = _22.w * _12._m3.w;   // tangentOS.w * unity_WorldTransformParams.w
    vec3 _260 = vec3(_44) * _40; // tangentOS.w * unity_WorldTransformParams.w * binormalWS
    _33 = vec4(_260.x, _260.y, _260.z, _33.w);  // binormalWS
}

layout(set = 2, binding = 0) uniform samplerCube _41;   // EnvCube
layout(set = 2, binding = 1) uniform sampler2D _45;     // tileLightIndexTexture
layout(set = 2, binding = 2) uniform sampler2D _46;     // diffuseTex
layout(set = 2, binding = 3) uniform sampler2D _47;     // paramTex
layout(set = 2, binding = 4) uniform sampler2D _48;     // normalTex
layout(set = 2, binding = 5) uniform sampler2D _49;     // detailNormalTex
layout(set = 2, binding = 6) uniform sampler2D _50;     // TintMask rgb 可能控制脸红
layout(set = 2, binding = 7) uniform sampler2D _51;     // decalTex
layout(set = 2, binding = 8) uniform sampler2D _52;     // detailTex
layout(set = 2, binding = 9) uniform sampler2D _53;     // sssLightColorTex
layout(set = 2, binding = 10) uniform sampler2D _54;    // shdowAndAOTexture
layout(set = 2, binding = 11) uniform samplerCube _55;

layout(location = 0) in vec4 _57;   // uvs  打包的UV坐标
layout(location = 5) in vec3 _59;   // positionWS
layout(location = 1) in vec4 _60;   // normalWS (w分量 存入viewDir)
layout(location = 2) in vec4 _61;   // tangentWS
layout(location = 3) in vec4 _62;   // binormalWS 
layout(location = 4) in vec4 _63;   // positionCS
layout(location = 0) out vec4 _65;  // color
layout(location = 1) out float _67;
vec3 _2438 = vec3(255.0);
uint _2477;
vec3 _2479 = vec3(255.0);

void _134()
{
    vec2 _140 = texture(_47, _57.xy).xz;           // 
    _70 = vec4(_140.x, _140.y, _70.z, _70.w); // vec2 metallic_roughness = texture(_47, _57.xy).xz; // _140, _70
    _113.x = _57.x >= 0.5;
    _119 = float(_113.x);     // // uv.x > 0.5    isRight
    _76.x = _113.x ? 0.0 : _27._m17;
    _76.x = (_27._m16 * _119) + _76.x; // (isRight ? 0 : _27._m17) + _27._m16 * isRight    isSelect   _24._m13 right用哪个   _24._m14 left用哪个
    _79 = texture(_46, _57.xy, _14._m7);  // vec4 albedo_base = texture(_46, _57.xy); // _79
    _110 = _57.xy + vec2(-0.5, -0.4709999859333038330078125); // uv.xy + float2(-0.5, 0.471)
    _113 = greaterThanEqual(abs(_110.xyxy), vec4(0.100000001490116119384765625, 0.0489999987185001373291015625, 0.100000001490116119384765625, 0.0489999987185001373291015625)).xy;
    _110.x = float(_113.x);  // is_outside_x = (abs(_110.x) >= 0.100) ? 1.0 : 0.0;  is_outside_y = (abs(_110.y) >= 0.049) ? 1.0 : 0.0;
    _110.y = float(_113.y);   // 定义一个中心矩形: 中心点: (0.5, 0.471) 半宽: 0.1 (总宽度 0.2)  半高: 0.049 (总高度 0.098)
    _101 = max(_110.y, _110.x);  //   max(is_outside_x, is_outside_y)   isOutsideRect
    _81 = texture(_52, _57.zw, _14._m7);  //  vec4 albedo_detail = texture(_52, _57.zw); // _81
    vec3 _218 = (-_79.xyz) + _81.xyz;
    _82 = vec4(_218.x, _218.y, _218.z, _82.w);
    vec3 _225 = _81.www * _82.xyz;
    _82 = vec4(_225.x, _225.y, _225.z, _82.w);
    vec3 _235 = (_76.xxx * _82.xyz) + _79.xyz;
    _82 = vec4(_235.x, _235.y, _235.z, _82.w);      // lerp(albedo_base, albedo_detail, isSelect * albedo_detail.a)
    vec3 _244 = _82.xyz * _27._m1.xyz;          
    _86 = vec4(_244.x, _244.y, _244.z, _86.w);     // albedo = blended_albedo * color_tint;
    _87 = (_82.xyz * _27._m1.xyz) + (-_27._m2.xyz);
    _87 = (_79.www * _87) + _27._m2.xyz;          // albedoM lerp(_27._m2.xyz, albedo, albedo_base.a)  比如控制嘴唇靠近里面的颜色     
    _87 = ((-_82.xyz) * _27._m1.xyz) + _87;     // 
    vec3 _288 = (vec3(_27._m15, _27._m15, _27._m15) * _87) + _86.xyz;
    _86 = vec4(_288.x, _288.y, _288.z, _86.w);       // albedoMM lerp(albedo, albedoM, _27._m15) 控制比例
    vec3 _300 = (_82.xyz * _27._m1.xyz) + (-_86.xyz);
    _82 = vec4(_300.x, _300.y, _300.z, _82.w);
    vec3 _310 = (vec3(_101) * _82.xyz) + _86.xyz;     
    _82 = vec4(_310.x, _310.y, _310.z, _82.w);  // albedo  lerp(albedoMM, albedo, isOutsideRect)  比如只会在嘴部
    _114 = _79.w + (-1.0);
    _101 = _114 * _101;
    _101 = (_27._m11 * _101) + 1.0;       // lerp(1, albedo_base.a, isOutsideRect * _27._m11)   brightM
    _78 = vec3(_101) * _82.xyz;     //  albedo * brightM     比如控制嘴唇靠近里面暗一点 加AO  albedo
    _101 = _70.y * _27._m12;        // metallic_roughness.y * _27._m12
    _82 = texture(_51, _57.xy);     // decalTex
    _100.x = _82.w * _27._m4.w;     
    _80 = (_82.xyz * _27._m4.xyz) + (-_78);  // _27._m4        decalColor
    _100 = (_100.xxx * _80) + _78;          //albedo  lerp(albedo, decalTex.rgb * _27._m4.xyz, _82.w * _27._m4.w)
    _79 = texture(_50, _57.xy);         // 
    _114 = dot(_79, _27._m8);
    vec3 _376 = _27._m7.xyz + vec3(-1.0);
    _86 = vec4(_376.x, _376.y, _376.z, _86.w);
    vec3 _385 = (vec3(_114) * _86.xyz) + vec3(1.0);
    _86 = vec4(_385.x, _385.y, _385.z, _86.w);  // tintControl = lerp(1, _27._m7.xyz, dot(TintMask.rgb, _27._m8))
    _100 *= _86.xyz;                         // albedo * tintControl     控制害羞脸红耳朵红 ？？
    vec2 _396 = texture(_48, _57.xy).xy;     
    _79 = vec4(_396.x, _396.y, _79.z, _79.w);    // normalTex
    _115 = texture(_49, _57.zw).xy;              // detailNormalTex
    vec2 _410 = (_79.xy * vec2(2.0)) + vec2(-1.0);
    _86 = vec4(_410.x, _410.y, _86.z, _86.w);
    _114 = dot(_86.xy, _86.xy);
    _114 = min(_114, 1.0);
    _114 = (-_114) + 1.0;
    _86.z = sqrt(_114);                 //  normalZ
    vec2 _428 = (_115 * vec2(2.0)) + vec2(-1.0);
    _87 = vec3(_428.x, _428.y, _87.z);
    _114 = dot(_87.xy, _87.xy);
    _114 = min(_114, 1.0);
    _114 = (-_114) + 1.0;
    _87.z = sqrt(_114);                 //  detailNormalZ
    _87 = (-_86.xyz) + _87;
    _87 = _81.www * _87;
    vec3 _459 = (_76.xxx * _87) + _86.xyz;
    _76 = vec4(_459.x, _76.y, _459.y, _459.z);     //normalTS lerp(normalZ, detailNormalZ, albedo_detail.a * isSelect)   isSelect 控制左右的混合比例
    _86.x = _60.w;
    _86.y = _61.w;
    _86.z = _62.w;                      // viewDirWS
    _121 = dot(_86.xyz, _86.xyz);       // 
    _121 = inversesqrt(_121);
    _87 = vec3(_121) * _86.xyz;         // viewDirWS
    _88 = _76.zzz * _62.xyz;
    _88 = (_76.xxx * _61.xyz) + _88;
    vec3 _501 = (_76.www * _60.xyz) + _88;       // noramlWS
    _76 = vec4(_501.x, _76.y, _501.y, _501.z);
    _122 = dot(_76.xzw, _76.xzw);
    _122 = inversesqrt(_122);
    vec3 _515 = _76.xzw * vec3(_122);
    _79 = vec4(_515.x, _515.y, _515.z, _79.w);   // noramlWS
    _79.w = 1.0;                           // SampleSH9
    _88.x = dot(_32._m0[0u], _79);
    _88.y = dot(_32._m0[1u], _79);
    _88.z = dot(_32._m0[2u], _79);
    _81 = _79.yzzx * _79.xyzz;
    _89.x = dot(_32._m0[3u], _81);
    _89.y = dot(_32._m0[4u], _81);
    _89.z = dot(_32._m0[5u], _81);
    _76.x = _79.y * _79.y;
    _76.x = (_79.x * _79.x) + (-_76.x);
    _88 += _89;
    vec3 _582 = (_32._m0[6u].xyz * _76.xxx) + _88;
    _76 = vec4(_582.x, _76.y, _582.y, _582.z);  // SampleSH9  end     bakedGI = SampleSHPixel()
    vec3 _588 = max(_76.xzw, vec3(0.0));
    _76 = vec4(_588.x, _76.y, _588.y, _588.z); // max(bakedGI, 0)
    _90.x = _63.x;
    _90.y = _63.y * _18._m8.x;
    vec2 _604 = _90.xy / _63.ww;
    _90 = vec4(_604.x, _604.y, _90.z, _90.w);  
    vec2 _611 = (_90.xy * vec2(0.5)) + vec2(0.5);   //  screenUV
    _90 = vec4(_611.x, _611.y, _90.z, _90.w);       //  screenUV
    _117 = _101 * 0.07999999821186065673828125;     // metallic_roughness.y * _27._m12 * 0.08 F0
    _122 = max(_70.x, 0.00999999977648258209228515625);  // max(metallic_roughness.x, 0.01)
    _69.x = dot(_79.xyz, _87);              // dot(normalWS, viewDirWS)  ndotv
    _69.x = max(_69.x, 0.0);                // max(ndotv, 0)
    _69.x += 9.9999997473787516355514526367188e-06;   // ndotv + 0.00001
    _81 = texture(_54, _90.xy);                 // shadow_ao 
    _88.x = _81.x + (-1.0);
    _88.x = (_24._m6 * _88.x) + 1.0;    //  lerp(1, shadow_ao.x, _21._m6) shadow   _21._m6 shdowStrength
    vec3 _654 = texture(_53, _90.xy).xyz;   
    _91 = vec4(_654.x, _654.y, _91.z, _654.z); //vec3 sss_lighting = texture(_53, screenUV).xyz; // _654, _91
    _102 = dot(_79.xyz, _14._m1.xyz);  // dot(normalWS, _14._m1.xyz)  ndotl
    _102 = max(_102, 0.0);          // max(0, ndotl)
    vec3 _673 = (_86.xyz * vec3(_121)) + _14._m1.xyz;   // viewDirWS + LightDir
    _95 = vec4(_673.x, _673.y, _673.z, _95.w);
    _125 = dot(_95.xyz, _95.xyz);
    _125 = max(_125, 6.103515625e-05);
    _125 = inversesqrt(_125);
    vec3 _690 = vec3(_125) * _95.xyz;            
    _95 = vec4(_690.x, _690.y, _690.z, _95.w);      // halfDir
    _95.w = dot(_87, _95.xyz);                  // dot(halfDir, viewDirWS)   vdoth
    _95.x = dot(_79.xyz, _95.xyz);              // dot(normalWS, halfDir)   ndoth
    vec2 _707 = max(_95.xw, vec2(0.0));         // max(vdoth ndoth, 0)
    _95 = vec4(_707.x, _95.y, _95.z, _707.y); //ndoth  vdoth  
    _89 = vec3(_102) * _24._m2.xyz;   // ndotl * _LightColor
    _106 = 0.0 < _102;       // ndotl > 0
    _116.x = _122 * _122;   // metallic_roughness.x * metallic_roughness.x      roughness^2  // D_GGX
    _116 = max(_116.xx, vec2(0.00999999977648258209228515625, 0.100000001490116119384765625)); max(roughness^2, 0.01   0.1)
    _95.x = min(_95.x, 0.999000012874603271484375); // min(ndoth, 0.999)
    _95.x *= _95.x;             // ndoth * ndoth
    _123 = 1.0 / _116.x;       // 1 / roughness^2
    _118 = _116.x + (-_123);   // roughness^2 - 1 / roughness^2
    _95.x = (_95.x * _118) + _123;    // ndoth^2 * (roughness^2 - 1 / roughness^2) + 1 / roughness^2
    _95.x = 1.0 / _95.x;     // 1 / (ndoth^2 * (roughness^2 - 1 / roughness^2) + 1 / roughness^2)
    _95.x = min(_95.x, 10.0); // min(_95.x, 10)
    _95.x *= _95.x;   // d*d
    _95.x *= 0.3183098733425140380859375;  // D_GGX end      D
    _116.x = (-_116.y) + 1.0;             // 1 - roughness2 Vis_SmithJointApprox
    _98 = (_69.x * _116.x) + _116.y;
    _107 = (_102 * _116.x) + _116.y;
    _107 = _69.x * _107;
    _102 = (_102 * _98) + _107;
    _102 = 1.0 / _102;
    _102 *= 0.5;                   
    _102 = min(_102, 10.0);       // Vis_SmithJointApprox end G
    _125 = (-_95.w) + 1.0;       // F_Schlick   F_Schlick( float3 SpecularColor, float VoH )
    _99.x = _125 * _125;
    _99.x *= _99.x;
    _108 = _125 * _99.x;       // Pow5( 1 - VoH )       F90 = saturate(50.0 * F0.g) 见https://google.github.io/filament/Filament.md.html#toc5.6.2    和 4.8
    _101 *= 4.0;   // DielectricSpecularToF0(half Specular)  half(0.08f * Specular);   50.0 * SpecularColor.g    50 * 0.08 = 4               
    _101 = clamp(_101, 0.0, 1.0);     // saturate( metallic_roughness.y * _27._m12 * 4)   // metallic_roughness有点像是自定义DielectricSpecular
    _125 = ((-_99.x) * _125) + 1.0;       // 1 - Pow5( 1 - VoH )
    _125 = _117 * _125;    // metallic_roughness.y * _27._m12 * 0.08 * (1 - Pow5( 1 - VoH ))   F0 *(1 -fc)
    _125 = (_101 * _108) + _125;       //   F_Schlick end F90 * fc  Pow5( 1 - VoH ) * saturate( metallic_roughness.y * _27._m12 * 4) + 
    _107 = _95.x * _125;
    _102 *= _107;                      // D * F * G
    _89 *= vec3(_102);                                  // ndotl * _LightColor * DFG
    _89 = mix(vec3(0.0), _89, bvec3(_106));       // lerp(0, ndotl * _LightColor * DFG, ndotl > 0)
    _89 = _88.xxx * _89;                        // shadow * lerp(0, ndotl * _LightColor * DFG, ndotl > 0)    specularColor
    _89 = (_100 * _91.xyw) + _89;                   // albedo * sss_lighting + specularColor     directLighting      (diffuseColor + specularColor)   
    _88.x = dot(_79.xyz, _24._m0.xyz);           // dot(normalWS, skyLightDir)   ndotSl
    _88.x = max(_88.x, 0.0);                // max(0, ndotSl)
    _100 = (_86.xyz * vec3(_121)) + _24._m0.xyz;   // (viewDirWS + skyLightDir) halfDirSL
    _90.x = dot(_100, _100);
    _90.x = max(_90.x, 6.103515625e-05);
    _90.x = inversesqrt(_90.x);
    _100 *= _90.xxx;                    // halfDirSL
    _90.x = dot(_87, _100);             // dot(viewDirWS, halfDirSL)      vdotHSL
    _90.x = max(_90.x, 0.0);            // max(0, vdotHSL)
    _100.x = dot(_79.xyz, _100);        // dot(noramlWS, halfDirSL)      ndotHSL
    _100.x = max(_100.x, 0.0);          // max(0, ndotHSL)
    vec3 _928 = _88.xxx * _24._m3.xyz;         
    _86 = vec4(_928.x, _928.y, _928.z, _86.w);   // ndotSl * _SkyColor
    _113.x = 0.0 < _88.x;                  // ndotSl > 0
    _100.x = min(_100.x, 0.999000012874603271484375);   // min(ndotSl, 0.999)
    _100.x *= _100.x;                         // D_GGX
    _100.x = (_100.x * _118) + _123;
    _100.x = 1.0 / _100.x;
    _100.x = min(_100.x, 10.0);
    _100.x *= _100.x;
    _100.x *= 0.3183098733425140380859375; // D_GGX end      D
    _121 = (_88.x * _116.x) + _116.y; // Vis_SmithJointApprox
    _121 = _69.x * _121;
    _121 = (_88.x * _98) + _121;
    _121 = 1.0 / _121;
    _121 *= 0.5;
    _121 = min(_121, 10.0);      // Vis_SmithJointApprox end G
    _69.x = (-_90.x) + 1.0;   // F_Schlick
    _119 = _69.x * _69.x;
    _119 *= _119;
    _90.x = _69.x * _119;
    _69.x = ((-_119) * _69.x) + 1.0;
    _69.x = _117 * _69.x;        
    _69.x = (_101 * _90.x) + _69.x; //  //   F_Schlick end 
    _101 = _100.x * _69.x;         
    _101 = _121 * _101;               // DFG1
    vec3 _1044 = _86.xyz * vec3(_101);         // ndotSl * _SkyColor * DFG1
    _86 = vec4(_1044.x, _1044.y, _1044.z, _86.w);
    vec3 _1052 = mix(vec3(0.0), _86.xyz, bvec3(_113.x));   // lerp(0, ndotSl * _SkyColor * DFG1, ndotSl > 0)
    _86 = vec4(_1052.x, _1052.y, _1052.z, _86.w);         // 
    vec3 _1061 = (_86.xyz * _81.www) + _89;      // shadow_ao.a * ndotSl * _SkyColor * DFG1 + directLighting
    _86 = vec4(_1061.x, _1061.y, _1061.z, _86.w);  // directAndSkyLightingColor
    _101 = dot(-_87, _79.xyz);      // dot(-viewDirWS, noramlWS)
    _101 += _101;
    _88 = (_79.xyz * (-vec3(_101))) + (-_87);     //    reflect(-viewDirWS, noramlWS)
    _101 = ((-_122) * 0.699999988079071044921875) + 1.7000000476837158203125;   // -roughness * 0.7 + 1.7
    _101 *= _122;
    _101 *= 6.0;         // roughness * (-roughness * 0.7 + 1.7) * 6     lod
    _70 = textureLod(_41, _88, _101); //  EnvCube
    _101 = _70.w + (-1.0);
    _101 = (_21._m4.w * _101) + 1.0;       // lerp(1, EnvCube.a, _21._m4.w) 
    _101 = max(_101, 0.0);     // max(0, envW)
    _101 = log2(_101);
    _101 *= _21._m4.y;
    _101 = exp2(_101);           // pow(envW, _21._m4.y)
    _101 *= _21._m4.x;          // _21._m4.x * envW
    _88 = _70.xyz * vec3(_101);        // EnvCube.rgb *  _21._m4.x * envW
    vec3 _1127 = _76.xzw * _88;         // bakedGI * EnvCube.rgb *  _21._m4.x * envW   // envGI
    _76 = vec4(_1127.x, _1127.y, _1127.z, _76.w);
    vec3 _1134 = vec3(_117) * _76.xyz;             
    _76 = vec4(_1134.x, _1134.y, _1134.z, _76.w);       // F0 * envGI         // specularGI
    vec3 _1149 = (_76.xyz * vec3(_24._m5, _24._m5, _24._m5)) + _86.xyz;  // F0 * envGI * _24._m5 + directAndSkyLightingColor 强度
    _76 = vec4(_1149.x, _1149.y, _1149.z, _76.w);  // directAndSkyLightingColor
    vec2 _1158 = _59.xz + (-_14._m4.xy);
    _69 = vec4(_1158.x, _1158.y, _69.z, _69.w);   // // positionWS.xz - 14._m4.xy
    vec2 _1166 = _69.xy / _14._m4.zw;
    _69 = vec4(_1166.x, _1166.y, _69.z, _69.w);
    _70 = texture(_45, _69.xy);             // tileLightIndex    rgba
    _69 = (_70 * vec4(255.0)) + vec4(0.5);
    _69 = floor(_69);   // 转换为整数          解码出4个光源的索引     lightIndexs
    _81 = (-_81) + vec4(1.0);            // 1 - shadow_ao
    _85 = lessThan(_69, vec4(30.0));         //  lightIndexs < 30
    if (_85.x)
    {
        _93 = uint(_69.x);
        _86.x = dot(_81, _9._m6[int(_93)]);
    }
    else
    {
        _86.x = 1.0;
    }
    if (_85.y)
    {
        _93 = uint(_69.y);
        _86.y = dot(_81, _9._m6[int(_93)]);
    }
    else
    {
        _86.y = 1.0;
    }
    if (_85.z)
    {
        _93 = uint(_69.z);
        _86.z = dot(_81, _9._m6[int(_93)]);
    }
    else
    {
        _86.z = 1.0;
    }
    if (_85.w)
    {
        _93 = uint(_69.w);
        _86.w = dot(_81, _9._m6[int(_93)]);
    }
    else
    {
        _86.w = 1.0;
    }
    _94 = _69.x < 255.0;    // 255的index为没有light
    if (_94)  
    {
        _81 = (vec4(_24._m6) * (-_86)) + vec4(1.0);   //  获取shadow
        _94 = 0.001000000047497451305389404296875 < _81.x;  // 如果像素几乎完全在阴影中，则跳过光照计算
        if (_94)
        {
            _72 = int(_69.x);         // light_index 
            vec3 _1289 = ((-_59) * _9._m0[_72].www) + _9._m0[_72].xyz; // addLightDir // _addLightPos[0].xyz - positionWS * _addLightPos[0].w     w为方向光的时候为0
            _90 = vec4(_1289.x, _1289.y, _90.z, _1289.z);
            _95.x = dot(_90.xyw, _90.xyw);
            _95.x = max(_95.x, 1.1754943508222875079687365372222e-38);  // addLightDirLenSqr
            _105 = inversesqrt(_95.x);
            _99 = _90.xyw * vec3(_105);       // normalize(addLightDir)
            _125 = (_95.x * _9._m4[_72].x) + 1.0;  //(ax+b)/(cx+1)   b截距  a固定y轴截距控制曲线弯曲   c固定x和y轴截距控制曲线弯曲 自定义光源衰减曲线
            _125 = 1.0 / _125;
            _95.x = (_95.x * _9._m4[_72].y) + _9._m4[_72].z;
            _95.x = clamp(_95.x, 0.0, 1.0);
            _95.x *= _125;
            _125 = dot(_9._m5[_72].xyz, _99);
            _125 = (_125 * _9._m1[_72].x) + _9._m1[_72].y;
            _125 = clamp(_125, 0.0, 1.0);
            _125 *= _125;           //  atten * atten   AngleAttenuation
            _95.x = _125 * _95.x;   // float attenuation = DistanceAttenuation * AngleAttenuation
            _120 = dot(_79.xyz, _99);   // dot(noramlWS, addLightDir)
            _120 = max(_120, 0.0);    // ndotal
            vec3 _1377 = (_90.xyw * vec3(_105)) + _87;        // halfDirAL
            _90 = vec4(_1377.x, _1377.y, _90.z, _1377.z);
            _105 = dot(_90.xyw, _90.xyw);
            _105 = max(_105, 6.103515625e-05);
            _105 = inversesqrt(_105);
            vec3 _1393 = _90.xyw * vec3(_105);
            _90 = vec4(_1393.x, _1393.y, _90.z, _1393.z);        // normalize(halfDirAL)
            _90.x = dot(_79.xyz, _90.xyw);           // ndotHAL
            _90.x = max(_90.x, 0.0);                 // ndotHAL
            vec3 _1412 = vec3(_120) * _9._m3[_72].xyz;       // ndotal * addLightColor
            _86 = vec4(_1412.x, _1412.y, _1412.z, _86.w);
            vec3 _1419 = _95.xxx * _86.xyz;             // attenuation * ndotal * addLightColor
            _86 = vec4(_1419.x, _1419.y, _1419.z, _86.w);   // addLightRadiance
            _75 = 0.0 < _120;               //  ndotal > 0
            _120 = (_122 * 0.25) + 0.25;     // metallic_roughness.x * 0.25 + 0.25
            _90.x = min(_90.x, 0.999000012874603271484375);  // min(ndoth, 0.999)
            _90.x *= _90.x;     // roughness^2  // D_GGX
            _90.x = (_90.x * _118) + _123;
            _90.x = 1.0 / _90.x;
            _90.x = min(_90.x, 10.0);
            _90.x *= _90.x;    // d*d
            _90.x *= 0.3183098733425140380859375;  // D_GGX end      D
            _120 *= _90.x;  //D * G  ( metallic_roughness.x * 0.25 + 0.25) MobileSpecularGGXInner的 vis
            _120 *= _117;   //D * G * F0  // 
            vec3 _1474 = _86.xyz * vec3(_120);   // addLightRadiance * specluar
            _86 = vec4(_1474.x, _1474.y, _1474.z, _86.w);  // addSpecluarC
            vec3 _1481 = mix(vec3(0.0), _86.xyz, bvec3(_75));   // lerp(0, addSpecluarC, ndotal > 0)
            _86 = vec4(_1481.x, _1481.y, _1481.z, _86.w);
            vec3 _1488 = _81.xxx * _86.xyz;  // addSpecluarC * shadow
            _86 = vec4(_1488.x, _1488.y, _1488.z, _86.w); // addSpecluarC
        }
        else
        {
            _86.x = 0.0;
            _86.y = 0.0;
            _86.z = 0.0;  // addSpecluarC
        }
        _75 = _69.y < 255.0;
        if (_75)
        {
            _75 = 0.001000000047497451305389404296875 < _81.y;
            if (_75)
            {
                _72 = int(_69.y);
                vec3 _1520 = ((-_59) * _9._m0[_72].www) + _9._m0[_72].xyz;
                _90 = vec4(_1520.x, _1520.y, _90.z, _1520.z);
                _100.x = dot(_90.xyw, _90.xyw);
                _100.x = max(_100.x, 1.1754943508222875079687365372222e-38);
                _95.x = inversesqrt(_100.x);
                _99 = _90.xyw * _95.xxx;
                _105 = (_100.x * _9._m4[_72].x) + 1.0;
                _105 = 1.0 / _105;
                _100.x = (_100.x * _9._m4[_72].y) + _9._m4[_72].z;
                _100.x = clamp(_100.x, 0.0, 1.0);
                _100.x *= _105;
                _105 = dot(_9._m5[_72].xyz, _99);
                _105 = (_105 * _9._m1[_72].x) + _9._m1[_72].y;
                _105 = clamp(_105, 0.0, 1.0);
                _105 *= _105;
                _100.x *= _105;
                _120 = dot(_79.xyz, _99);
                _120 = max(_120, 0.0);
                vec3 _1608 = (_90.xyw * _95.xxx) + _87;
                _90 = vec4(_1608.x, _1608.y, _90.z, _1608.z);
                _95.x = dot(_90.xyw, _90.xyw);
                _95.x = max(_95.x, 6.103515625e-05);
                _95.x = inversesqrt(_95.x);
                vec3 _1629 = _90.xyw * _95.xxx;
                _90 = vec4(_1629.x, _1629.y, _90.z, _1629.z);
                _90.x = dot(_79.xyz, _90.xyw);
                _90.x = max(_90.x, 0.0);
                _88 = vec3(_120) * _9._m3[_72].xyz;
                _88 = _100.xxx * _88;
                _75 = 0.0 < _120;
                _120 = (_122 * 0.25) + 0.25;
                _100.x = min(_90.x, 0.999000012874603271484375);
                _100.x *= _100.x;
                _100.x = (_100.x * _118) + _123;
                _100.x = 1.0 / _100.x;
                _100.x = min(_100.x, 10.0);
                _100.x *= _100.x;
                _100.x *= 0.3183098733425140380859375;
                _120 = _100.x * _120;
                _120 *= _117;
                _88 *= vec3(_120);
                _88 = mix(vec3(0.0), _88, bvec3(_75));
                vec3 _1714 = (_88 * _81.yyy) + _86.xyz;  // addSpecluarC += addSpecluarC * shadow 
                _86 = vec4(_1714.x, _1714.y, _1714.z, _86.w);
            }
            _75 = _69.z < 255.0;
            if (_75)
            {
                _75 = 0.001000000047497451305389404296875 < _81.z;
                if (_75)
                {
                    _72 = int(_69.z);
                    vec3 _1743 = ((-_59) * _9._m0[_72].www) + _9._m0[_72].xyz;
                    _90 = vec4(_1743.x, _1743.y, _90.z, _1743.z);
                    _100.x = dot(_90.xyw, _90.xyw);
                    _100.x = max(_100.x, 1.1754943508222875079687365372222e-38);
                    _110.x = inversesqrt(_100.x);
                    vec3 _1764 = _110.xxx * _90.xyw;
                    _95 = vec4(_1764.x, _1764.y, _95.z, _1764.z);
                    _99.x = (_100.x * _9._m4[_72].x) + 1.0;
                    _99.x = 1.0 / _99.x;
                    _100.x = (_100.x * _9._m4[_72].y) + _9._m4[_72].z;
                    _100.x = clamp(_100.x, 0.0, 1.0);
                    _100.x *= _99.x;
                    _99.x = dot(_9._m5[_72].xyz, _95.xyw);
                    _99.x = (_99.x * _9._m1[_72].x) + _9._m1[_72].y;
                    _99.x = clamp(_99.x, 0.0, 1.0);
                    _99.x *= _99.x;
                    _100.x *= _99.x;
                    _120 = dot(_79.xyz, _95.xyw);
                    _120 = max(_120, 0.0);
                    vec3 _1848 = (_90.xyw * _110.xxx) + _87;
                    _90 = vec4(_1848.x, _1848.y, _90.z, _1848.z);
                    _110.x = dot(_90.xyw, _90.xyw);
                    _110.x = max(_110.x, 6.103515625e-05);
                    _110.x = inversesqrt(_110.x);
                    vec3 _1869 = _110.xxx * _90.xyw;
                    _90 = vec4(_1869.x, _1869.y, _90.z, _1869.z);
                    _110.x = dot(_79.xyz, _90.xyw);
                    _110.x = max(_110.x, 0.0);
                    _88 = vec3(_120) * _9._m3[_72].xyz;
                    _88 = _100.xxx * _88;
                    _75 = 0.0 < _120;
                    _120 = (_122 * 0.25) + 0.25;
                    _100.x = min(_110.x, 0.999000012874603271484375);
                    _100.x *= _100.x;
                    _100.x = (_100.x * _118) + _123;
                    _100.x = 1.0 / _100.x;
                    _100.x = min(_100.x, 10.0);
                    _100.x *= _100.x;
                    _100.x *= 0.3183098733425140380859375;
                    _120 = _100.x * _120;
                    _120 *= _117;
                    _88 *= vec3(_120);
                    _88 = mix(vec3(0.0), _88, bvec3(_75));
                    vec3 _1954 = (_88 * _81.zzz) + _86.xyz;
                    _86 = vec4(_1954.x, _1954.y, _1954.z, _86.w);
                }
                _75 = _69.w < 255.0;
                if (_75)
                {
                    _75 = 0.001000000047497451305389404296875 < _81.w;
                    if (_75)
                    {
                        _72 = int(_69.w);
                        _100 = ((-_59) * _9._m0[_72].www) + _9._m0[_72].xyz;
                        _90.x = dot(_100, _100);
                        _90.x = max(_90.x, 1.1754943508222875079687365372222e-38);
                        _103 = inversesqrt(_90.x);
                        vec3 _1998 = _100 * vec3(_103);
                        _95 = vec4(_1998.x, _1998.y, _95.z, _1998.z);
                        _124 = (_90.x * _9._m4[_72].x) + 1.0;
                        _124 = 1.0 / _124;
                        _90.x = (_90.x * _9._m4[_72].y) + _9._m4[_72].z;
                        _90.x = clamp(_90.x, 0.0, 1.0);
                        _90.x *= _124;
                        _124 = dot(_9._m5[_72].xyz, _95.xyw);
                        _124 = (_124 * _9._m1[_72].x) + _9._m1[_72].y;
                        _124 = clamp(_124, 0.0, 1.0);
                        _124 *= _124;
                        _90.x = _124 * _90.x;
                        _120 = dot(_79.xyz, _95.xyw);
                        _120 = max(_120, 0.0);
                        _100 = (_100 * vec3(_103)) + _87;
                        _103 = dot(_100, _100);
                        _103 = max(_103, 6.103515625e-05);
                        _103 = inversesqrt(_103);
                        _100 *= vec3(_103);
                        _100.x = dot(_79.xyz, _100);
                        _100.x = max(_100.x, 0.0);
                        _87 = vec3(_120) * _9._m3[_72].xyz;
                        _87 = _90.xxx * _87;
                        _75 = 0.0 < _120;
                        _120 = (_122 * 0.25) + 0.25;
                        _100.x = min(_100.x, 0.999000012874603271484375);
                        _100.x *= _100.x;
                        _100.x = (_100.x * _118) + _123;
                        _100.x = 1.0 / _100.x;
                        _100.x = min(_100.x, 10.0);
                        _100.x *= _100.x;
                        _100.x *= 0.3183098733425140380859375;
                        _120 = _100.x * _120;
                        _120 *= _117;
                        _87 *= vec3(_120);
                        _87 = mix(vec3(0.0), _87, bvec3(_75));
                        vec3 _2161 = (_87 * _81.www) + _86.xyz;
                        _86 = vec4(_2161.x, _2161.y, _2161.z, _86.w);
                    }
                }
            }
        }
    }
    else
    {
        _86.x = 0.0;
        _86.y = 0.0;
        _86.z = 0.0;     // // addLightingSpecular
    }
    vec3 _2171 = _76.xyz + _86.xyz;    // addLightingSpecular + directAndSkyLightingColor    finalLightColor
    _76 = vec4(_2171.x, _2171.y, _2171.z, _76.w);       // finalLightColor
    vec3 _2183 = (_59 * vec3(100.0)) + (-_37._m14);     // vec3 pos_in_fog_volume将世界坐标缩放并偏移，转换到雾体积的局部坐标
    _69 = vec4(_2183.x, _2183.y, _2183.z, _69.w);
    _119 = dot(_69.xyz, _69.xyz);
    _119 = sqrt(_119);   // float dist_in_fog = length(pos_in_fog_volume)
    _90.x = _119 + (-_37._m8.x);   // _37._m8.x 是雾的起始距离
    _90.x = max(_90.x, 0.0);     // max(dist_in_fog -_37._m8.x, 0)
    _104 = 0.00999999977648258209228515625 < abs(_69.y);    //  计算高度雾 (Height Fog) 衰减
    _103 = _104 ? _69.y : 0.00999999977648258209228515625 //float y_coord = is_vertical ? pos_in_fog_volume.y : 0.01;
    _103 *= _37._m9.y;        // unreal CalculateLineIntegralShared
    _103 = max(_103, -127.0);
    _117 = exp2(-_103);    // float height_falloff = 1.0 - exp2(-height_density); //
    _117 = (-_117) + 1.0;
    _117 *= _37._m9.x;
    _103 = _117 / _103;  // LineIntegral
    _90.x *= _103;           // RayOriginTerms  CalculateLineIntegralShared
    _90.x = exp2(-_90.x);          // float transmittance = exp2(-_90.x); // _90.x ExponentialHeightLineIntegralShared * max(RayLength - DirectionalInscatteringStartDistance, 0.0f);
    _90.x = (-_90.x) + 1.0;         // transmittance = 1.0 - transmittance; 
    vec3 _2251 = _69.xyz / vec3(_119);        // vec3 dir_in_fog = pos_in_fog_volume / dist_in_fog; // _2251, _69
    _69 = vec4(_2251.x, _2251.y, _2251.z, _69.w);  
    _95.x = dot(_69.xz, _37._m0.xy); // ComputeInscatteringColor
    _95.z = dot(_69.xz, _37._m0.zw);
    _120 = _90.x * _37._m1;        // 
    _95.y = _69.y;
    _96 = textureLod(_55, _95.xyz, _120).xyz;  // 
    vec3 _2287 = _96 * _37._m10.xyz;      // FogData.VolumetricFogAlbedo
    _95 = vec4(_2287.x, _2287.y, _2287.z, _95.w);  // vec3 in_scattering 
    _117 = _119 + (-_37._m7);   // 另一个距离因子CalculateLineIntegralShared
    _117 = max(_117, 0.0); 
    _103 = _117 * _103;
    _103 = exp2(-_103);
    _103 = (-_103) + 1.0;       //  // DirectionalInscatteringFogFactor = 1.0 - DirectionalInscatteringFogFactor; 
    _69.x = dot(_69.xyz, _14._m1.xyz); // dot()
    _69.x = clamp(_69.x, 0.0, 1.0);
    _69.x = log2(_69.x);
    _69.x *= _37._m6.w;
    _69.x = exp2(_69.x);
    vec3 _2336 = _69.xxx * _37._m6.xyz;   
    _69 = vec4(_2336.x, _2336.y, _2336.z, _69.w);  // DirectionalLightInscattering pow(saturate(dot(CameraToReceiverNormalized, FogData.InscatteringLightDirection.xyz)), FogData.DirectionalInscatteringColor.w)
    vec3 _2343 = vec3(_103) * _69.xyz;     // DirectionalLightInscattering * (1 - DirectionalInscatteringFogFactor);
    _69 = vec4(_2343.x, _2343.y, _2343.z, _69.w);      // DirectionalInscattering
    _119 = (_119 * 0.00999999977648258209228515625) + (-_37._m12);  // _119 = (dist_in_fog * 0.01) - _37._m12;
    _119 /= _37._m13;           // _119 /= _37._m13;
    _119 = clamp(_119, 0.0, 1.0);
    _119 = max(_90.x, _119);     // _119 = max(transmittance, _119); // 混合因子至少和雾的遮挡度一样大
    vec3 _2370 = (_95.xyz * _90.xxx) + _69.xyz;  // 
    _69 = vec4(_2370.x, _2370.y, _2370.z, _69.w); // fogcolor (InscatteringColor) * (1 - ExpFogFactor) + DirectionalInscattering;
    _119 = (-_119) + 1.0;
    vec3 _2383 = (_76.xyz * vec3(_119)) + _69.xyz; // finalLightColor * (1 - transmittance) + fogcolor
    _65 = vec4(_2383.x, _2383.y, _2383.z, _65.w); // finalLightColor
    _76.x = _27._m18 + (-1.0);
    _76.x = (_14._m6 * _76.x) + 1.0;        // lerp(1, _27._m18, _14._m6)
    _65.w = _76.x;
    _67 = _76.x;       // alpha      // 如果focus 后续根据alpha判断
}



// 计算 dof 的 coc 存入apha 并放入相应color
layout(set = 2, binding = 0) uniform sampler2D _22;   // depthTex
layout(set = 2, binding = 1) uniform sampler2D _23;   // sceneTex

layout(location = 0) in vec2 _26;              // uv
layout(location = 0) out vec4 _28;
vec3 _301 = vec3(255.0);

void _53()
{
    _30.x = 2.0;                        
    _41.x = -1.0;
    _30.y = _8._m8.x * 2.0;
    _41.y = -_8._m8.x;
    vec2 _76 = (_30.xy * _26) + _41;  //positionCS ndc.x = uv.x * 2.0 - 1.0; ndc.y = (uv.y * 2.0 * _8._m8.x) - _8._m8.x; 
    _30 = vec4(_76.x, _76.y, _30.z, _30.w);   // positionRWS begin
    _31 = _30.yyyy * _15._m5[1u];
    _30 = (_15._m5[0u] * _30.xxxx) + _31; //
    _31.x = texture(_22, _26).x;         // scenedepth
    _39 = (_31.x * 2.0) + (-1.0);         // depth "Hidden/Universal Render Pipeline/ScreenSpaceShadows" 类似的device depth
    _34 = _31.x == 1.0;             // scenedepth == 1
    _30 = (_15._m5[2u] * vec4(_39)) + _30;
    _30 += _15._m5[3u];
    _42 = 1.0 / _30.w;      // positionRWS
    vec3 _130 = (_30.xyz * vec3(_42)) + _8._m5;   // positionWS    positionRWS + cameraPos
    _30 = vec4(_130.x, _130.y, _130.z, _30.w);
    vec3 _138 = (-_30.xyz) + _8._m6;           // viewDirWS
    _30 = vec4(_138.x, _138.y, _138.z, _30.w);
    _30.x = dot(_30.xyz, _30.xyz);
    _30.x = sqrt(_30.x);        // viewLen
    _30.x = _34 ? _18._m1 : _30.x;      // scenedepth == 1 ？ _18._m1 : viewLen
    vec2 _168 = (_30.xx * _18._m0.xz) + _18._m0.yw;    // viewLen * _18._m0.xz + _18._m0.yw
    _30 = vec4(_168.x, _168.y, _30.z, _30.w);         // dist_to_focus   近处远处
    vec2 _174 = clamp(_30.xy, vec2(0.0), vec2(1.0));
    _30 = vec4(_174.x, _174.y, _30.z, _30.w);        // FarNearFocus
    _36.x = log2(_30.y);
    _36.x *= _18._m3;
    _36.x = exp2(_36.x);           // pow(FarNearFocus.y, _18._m3)       // 对nearfocus曲线调节
    _37 = _30.y < _30.x;           // farNearFocus.y < farNearFocus.x
    _36.x = _37 ? _30.x : (-_36.x);  // cocFactor     // farNearFocus.y < farNearFocus.x ? farNearFocus.x : -FarNearFocus.y  负数是near
    _30 = texture(_23, _26);                    // sceneColor
    _43 = _30.w < 0.001000000047497451305389404296875;         // sceneColor.a < 0.001
    _36.x = _43 ? 0.0 : _36.x;          //  sceneColor.a < 0.001 ? 0 : _36.x   // cocFactor
    _43 = _36.x == 0.0;      //  bool no_effect = (cocFactor == 0.0)  
    _36.x *= _18._m2;          // cocFactor * _18._m2  dofIntensity
    _36.x *= _15._m10.x;        // dofIntensity * _15._m10.x    screenSize
    _28.w = _36.x * 0.5;           //  dofIntensity * _15._m10.x * 0.5    cocRadius
    _36 = _30.xyz * vec3(_18._m4, _18._m4, _18._m4);     // sceneColor.rgb * _18._m4   dimmdColor
    _36 = mix(_30.xyz, _36, bvec3(_43));     // lerp(sceneColor, dimmdColor, no_effect)
    vec3 _259 = max(_36, vec3(0.0));  
    _28 = vec4(_259.x, _259.y, _259.z, _28.w);     // sceneColor  cocRadius
}

// dof prefilter     输出二分之一分辨率  downsample
layout(set = 2, binding = 0) uniform sampler2D _12; // sceneColor   (alpha 为 CoC radius)

layout(location = 0) in vec2 _14;     // uv
layout(location = 0) out vec4 _16;

void _39()
{
    _18 = (_8._m0.zwzw * vec4(0.5, 0.5, -0.5, -0.5)) + _14.xyxy;  // uv.xyxy + float4(0.5, 0.5, -0.5, -0.5) * texelSize.xyxy
    _18 = min(_18, _8._m2.xyxy);        // min(uv, _8._m2.xyxy) // 限制范围
    _19 = texture(_12, _18.zw);         // sceneColor
    _18 = texture(_12, _18.xy);         // sceneColor1
    _22.x = max(_19.w, _18.w);         // max(sceneColor.a, sceneColor.a)  maxCoCRadius
    _23 = (_8._m0.zwzw * vec4(-0.5, 0.5, 0.5, -0.5)) + _14.xyxy;
    _23 = min(_23, _8._m2.xyxy);
    _24 = texture(_12, _23.xy);         // sceneColor2
    _23 = texture(_12, _23.zw);         // sceneColor3
    _28.x = max(_23.w, _24.w);
    _22.x = max(_28.x, _22.x);          //   maxCoCRadius       max_coc_in_block 
    _28.x = (-_19.w) + _22.x;      // float coc_diff_P11 = max_coc_in_block - sample_P11.w; // _28.x
    _25.y = ((-_28.x) * 64.0) + 1.0;  // cocRadius相似的贡献多     保持边缘
    _25.y = clamp(_25.y, 0.0, 1.0); // weights.y = clamp(1.0 - coc_diff_P11 * 64.0, 0.0, 1.0); // _25.y
    _28 = _19.xyz * _25.yyy;      // weights * sceneColor
    _27 = (-_18.w) + _22.x;
    _25.x = ((-_27) * 64.0) + 1.0;  // 类似
    _25.x = clamp(_25.x, 0.0, 1.0);
    _28 = (_18.xyz * _25.xxx) + _28; // weights * sceneColor1 + weight * sceneColor      blended_color 
    _27 = (-_24.w) + _22.x;   
    _25.z = ((-_27) * 64.0) + 1.0;
    _25.z = clamp(_25.z, 0.0, 1.0);
    _28 = (_24.xyz * _25.zzz) + _28;
    _27 = (-_23.w) + _22.x;
    _16.w = _22.x;                  // maxCoCRadius
    _25.w = ((-_27) * 64.0) + 1.0;
    _25.w = clamp(_25.w, 0.0, 1.0);
    _22 = (_23.xyz * _25.www) + _28;     // blended_color 
    _29 = dot(vec4(1.0), _25);     //  float total_weight = dot(vec4(1.0), weights);
    _29 = 1.0 / _29;
    _22 *= vec3(_29);      // blended_color / total_weight
    vec3 _217 = min(_22, vec3(200.0));   // vec3 final_color = min(blended_color, vec3(200.0)) 限制亮度
    _16 = vec4(_217.x, _217.y, _217.z, _16.w);      // maxCoCRadius
}

// 这一步会获取上一帧这里的输出
layout(set = 2, binding = 0) uniform sampler2D _24;     // preFrameColorCOCTex  alpha 为cocRadius
layout(set = 2, binding = 1) uniform sampler2D _25;     // currentColorCOCTex   alpha 为cocRadius
layout(set = 2, binding = 2) uniform sampler2D _26;     // motionVector  encode了的motion Vector

layout(location = 0) in vec2 _29;              // uv
layout(location = 1) in vec2 _30;               // posCS
layout(location = 0) out vec4 _32;

void _88()
{
    _36 = texture(_26, _29);
    _34 = _36 * vec4(255.0);    // vec4 encoded_mv = texture(_26, _29) * 255.0;
    _34 = roundEven(_34);      // 解码motion vector， 高8位 低8位
    _43 = uvec4(_34);       // 
    ivec2 _115 = ivec2(int(_43.x) << 8, int(_43.z) << 8);   // 高8位
    _40 = ivec3(_115.x, _40.y, _115.y);
    uvec2 _124 = _43.yw + uvec2(_40.xz);            // 加上低8位
    _43 = uvec4(_124.x, _124.y, _43.z, _43.w);      // motionVector 解码的
    vec2 _129 = vec2(_43.xy);
    _34 = vec4(_129.x, _129.y, _34.z, _34.w);       // motionVector 解码的 1 / 65536
    vec2 _139 = (_34.xy * vec2(6.1158403696026653051376342773438e-05)) + vec2(-2.0039775371551513671875); //motionVector * 4 - 2 将解码后的整数运动矢量转换到NDC空间 [-2, 2] 因为编码的这个范围
    _34 = vec4(_139.x, _139.y, _34.z, _34.w); // motionVector
    _75 = _15._m10.xy * vec2(0.5);       // texelSize.zw * 0.5   // 由于是图片是半分辨率
    _75 *= _34.xy;                         // motionVector * texelSize.zw * 0.5      pixelVector    unreal  BackN * OutputViewportSize.xy;
    vec2 _158 = (-_34.xy) + _30;          // posCS - motionVector           // HistoryScreenPosition = InputParams.ScreenPos - BackN;
    _34 = vec4(_158.x, _158.y, _34.z, _34.w);   //  oldPosCS
    _48 = abs(_75) + abs(_75);   // abs(pixelVector)* 2   // absVector
    _75.x = dot(_75, _75);
    _75.x = sqrt(_75.x);          // pixelVectorLen
    _77 = _48.y + _48.x;          // absVector.y + absVector.x
    _77 = min(_77, 1.0);          // min(absVector.y + absVector.x, 1) AddAliasing 有点类似unreal HistoryBlur = saturate(abs(BackTemp.x) * HistoryBlurAmp + abs(BackTemp.y) * HistoryBlurAmp);
    _48 = (_15._m10.zw * vec2(0.0, 2.0)) + _29;    // texelSize.xy * float2(0, 2) +  uv   当前帧颜色纹理(_25)进行3x3的十字形采样
    _49 = textureLod(_25, _48, 0.0);          // colorCOC     //见unity DoTemporalAA   4个采样
    _53.x = _49.y + 1.0;
    _53.x = 1.0 / _53.x;
    vec3 _207 = _49.xyz * _53.xxx;                // colorCOC.rgb * (1 / (1 + colorCOC.g))      SceneToWorkingSpace  unity taa 有点类似但是把linear转为ldr 很奇怪
    _53 = vec4(_207.x, _207.y, _207.z, _53.w);        // sceneColor
    _56.x = dot(_53.xzy, vec3(0.25, 0.25, 0.5));    // RGBToYCoCg
    _56.y = dot(_53.xz, vec2(0.5, -0.5));
    _56.z = dot(_53.xzy, vec3(-0.25, -0.25, 0.5));
    _48 = (_15._m10.zw * vec2(0.0, -2.0)) + _29;  // colorCOC1      SceneToWorkingSpace end
    _54 = textureLod(_25, _48, 0.0);
    _78 = _54.y + 1.0;
    _78 = 1.0 / _78;
    vec3 _248 = _54.xyz * vec3(_78);
    _58 = vec4(_248.x, _248.y, _248.z, _58.w);
    _60.x = dot(_58.xzy, vec3(0.25, 0.25, 0.5));
    _60.y = dot(_58.xz, vec2(0.5, -0.5));
    _60.z = dot(_58.xzy, vec3(-0.25, -0.25, 0.5));
    _57 = (_15._m10.zwzw * vec4(-2.0, 0.0, 2.0, 0.0)) + _29.xyxy;
    _62 = textureLod(_25, _57.xy, 0.0);
    _59 = textureLod(_25, _57.zw, 0.0);
    _78 = _62.y + 1.0;
    _78 = 1.0 / _78;
    vec3 _288 = vec3(_78) * _62.xyz;
    _63 = vec4(_288.x, _288.y, _288.z, _63.w);
    _64.x = dot(_63.xzy, vec3(0.25, 0.25, 0.5));
    _64.y = dot(_63.xz, vec2(0.5, -0.5));
    _64.z = dot(_63.xzy, vec3(-0.25, -0.25, 0.5));
    vec3 _305 = min(_60, _64);
    _63 = vec4(_305.x, _305.y, _305.z, _63.w);
    _63.w = min(_54.w, _62.w);
    _53.w = max(_54.w, _62.w);
    _78 = _59.y + 1.0;
    _78 = 1.0 / _78;
    vec3 _330 = vec3(_78) * _59.xyz;
    _65 = vec4(_330.x, _330.y, _330.z, _65.w);
    _66.x = dot(_65.xzy, vec3(0.25, 0.25, 0.5));
    _66.y = dot(_65.xz, vec2(0.5, -0.5));
    _66.z = dot(_65.xzy, vec3(-0.25, -0.25, 0.5));
    _61 = texture(_25, _29);
    _78 = _61.y + 1.0;
    _78 = 1.0 / _78;
    vec3 _357 = vec3(_78) * _61.xyz;
    _65 = vec4(_357.x, _357.y, _357.z, _65.w);
    _67.x = dot(_65.xzy, vec3(0.25, 0.25, 0.5));
    _67.y = dot(_65.xz, vec2(0.5, -0.5));
    _67.z = dot(_65.xzy, vec3(-0.25, -0.25, 0.5));        // 十字采样  centerCol
    vec3 _374 = min(_66, _67);
    _65 = vec4(_374.x, _374.y, _374.z, _65.w);
    _65.w = min(_59.w, _61.w);
    _58.w = max(_59.w, _61.w);
    _63 = min(_63, _65);                                // boxMin
    vec3 _395 = min(_56, _63.xyz);
    _63 = vec4(_395.x, _395.y, _395.z, _63.w);          // boxMin
    _78 = min(_49.w, _63.w);                       // boxMinCoc
    vec3 _405 = max(_60, _64);
    _53 = vec4(_405.x, _405.y, _405.z, _53.w);
    _64 *= vec3(_20._m0[1u]);
    _60 = (_60 * vec3(_20._m0[0u])) + _64;           // 类似 unreal FilterCurrentFrameInputSamples
    _60 = (_67 * vec3(_20._m0[2u])) + _60;
    _60 = (_66 * vec3(_20._m0[3u])) + _60;
    vec3 _437 = max(_66, _67);
    _58 = vec4(_437.x, _437.y, _437.z, _58.w);
    _53 = max(_53, _58);
    _60 = (_56 * vec3(_20._m0[4u])) + _60;           // 对采样做加权和 filterColor = WeightedAverage(ycocg_center, ycocg_up, ...);   FilterCurrentFrameInputSamples
    _56 = max(_56, _53.xyz);                    // boxMax                   
    _79 = max(_49.w, _53.w);                    // boxMaxCoc
    _80 = (-_63.x) + _56.x;                  // 计算TAA的 rejection    类似unreal  factor float LumaContrast = LumaMax - LumaMin;
    _64.x = (_80 * 128.0) + 1.0;
    _64.x = 1.0 / _64.x;                        // _64.x = 1.0 / (_80 * 128.0 + 1.0);   // rcp(1.0 + LumaContrast * LumaContrastFactor)
    _64.x = (_77 * 0.5) + _64.x;                //AddAliasing  AddAliasing * 0.5 + rcp(1.0 + LumaContrast * LumaContrastFactor) float AddAliasing = saturate(HistoryBlur) * 0.5;
    _64.x = clamp(_64.x, 0.0, 1.0);             // saturate(AddAliasing)
    _48 = (_15._m10.zw * vec2(4.0)) + abs(_30);    // texelSize.xy * 4 + abs(posCS)    offPos
    _48.x = max(_48.y, _48.x);                // max(offPos.x, offPos.y)
    _52.x = _48.x >= 1.0;                      // isOutScreen    max(offPos.x, offPos.y) > 1
    _60 = mix(_60, _67, bvec3(_52.x));        // lerp(filterColor, centerCol, isOutScreen)  采样区域在屏幕外 就用原来颜色
    _60 = (-_67) + _60;
    _60 = (_64.xxx * _60) + _67;                    // originCol  lerp(centerCol, filterColor, AddAliasing)        需要拒的时候使用模糊的颜色 当场景不稳定时
    _48.x = max(abs(_34.y), abs(_34.x));            // max(abs(oldPosCS.x), abs(oldPosCS.y))
    _52.x = _48.x >= 1.0;                           // isOldOutScreen 
    _73 = (_15._m10.zw * vec2(2.0)) + vec2(-1.0);      // texeSize.xy * 2 - 1    
    vec2 _542 = max(_34.xy, _73);                    // max(oldPosCS, rectMin)
    _34 = vec4(_542.x, _542.y, _34.z, _34.w);
    _73 = ((-_15._m10.zw) * vec2(2.0)) + vec2(1.0);   // 1 - texeSize.xy * 2
    vec2 _555 = min(_34.xy, _73);               // min(oldPosCS, rectMax) 限制oldPosCs范围
    _68 = vec3(_555.x, _555.y, _68.z);     // oldPosCS
    _68.z = _68.y * _8._m8.x;           // 是否倒转y
    vec2 _568 = (_68.xz * vec2(0.5)) + vec2(0.5);           // oldPosCS * 0.5 + 0.5
    _34 = vec4(_568.x, _568.y, _34.z, _34.w);         // oldPosUV
    _54 = textureLod(_24, _34.xy, 0.0);         // historyColorCoc             
    _64.x = _54.y + 1.0;
    _64.x = 1.0 / _64.x;
    _64 = _54.xyz * _64.xxx;                    // hisCol  historyColorCoc.rgb / (1 + historyColorCoc.g)
    _78 = max(_78, _54.w);                      // hisCoc  max(boxMinCoc, historyColorCoc.a)            unreal ClampHistory(
    _78 = min(_79, _78);                        // min(hisCoc, boxMaxCoc)
    _46 = abs(_78) >= 0.100000001490116119384765625;   // hisCoc > 0.1
    _65.y = dot(_64.xz, vec2(0.5, -0.5));
    _65.z = dot(_64.xzy, vec3(-0.25, -0.25, 0.5));
    _65.x = dot(_64.xzy, vec3(0.25, 0.25, 0.5));         // hisCol     RGBToYCoCg
    _64 = max(_63.xyz, _65.xyz);              // max(hisCol, boxMin)         
    _64 = min(_56, _64);                   // // max(hisCol, boxMax)         
    _64 = mix(_64, _60, bvec3(_52.x));          //  hisColFinal    lerp(hisCol, originCol, isOldOutScreen)   历史超出屏幕无效
    _64 = (-_60) + _64;                 
    _71 = max(_75.x, 1.0); //   max(pixelVectorLen, 1)         
    _71 = _75.x / _71;            // plen  pixelVectorLen / max(pixelVectorLen, 1.0);             // 相当于 min(pixelVectorLen, 1)
    _78 = _71 * 0.125;                      // plen * 0.125              
    _71 = (_77 * 0.125) + 0.125;     // AddAliasing * 0.125 + 0.125       absL            // _71 = remap(_77, 0.0, 1.0, 0.125, 0.25)
    _75.x = _71 * _77;                        // AddAliasing * absL
    _75.x = (_75.x * 8.0) + 1.0;         // AddAliasing * absL * 8 + 1         absL_off  _75.x = remap(_77, 0, 1, 0.125, 0.25) * _77 这个二次函数放大了快速移动时的响应，同时保持了慢速移动时的平滑。
    _79 = _63.x + (-_65.x);                // boxMin.Y -  hisCol.Y
    vec3 _664 = _63.xyz + (-vec3(_20._m2));
    _63 = vec4(_664.x, _664.y, _664.z, _63.w);     // boxMin - _20._m2      是否有自定义范围
    _52 = lessThan(_65.xyzx, _63.xyzx).xyz;      // hisCol < boxMin - _20._m2
    _63.x = _56.x + (-_65.x);                // boxMax.Y -  hisCol.Y
    _56 += vec3(_20._m2); 
    _69 = lessThan(_56.xyzx, _65.xyzx).xyz;        // boxMax < hisCol + _20._m2
    _56.x = min(abs(_79), abs(_63.x));     // min(abs(boxMin.Y -  hisCol.Y), abs(boxMax.Y -  hisCol.Y))      minYDiff
    _74 = _71 * _56.x;             // absL * minYDiff        即使物体没有移动，如果它的颜色发生了剧烈变化（minYDiff很大），算法依然会认为这里有一定概率是Disocclusion
    _56.x = _80 + _56.x;
    _56.x = 1.0 / _56.x;        //1 / (LumaContrast + minYDiff)           luma_contrast (_80) 代表了当前帧邻域本身的“混乱程度”    一个像素的颜色发生剧烈变化
    _71 = _75.x * _74;                //          相当于自身邻域变化大 就越需要模糊
    _56.x *= _71;                    // absL_off * absL ( minYDiff / (LumaContrast + minYDiff) )    distC       // LumaContrast这里表示本身周围像素颜色就变化剧烈
    _56.x = clamp(_56.x, 0.0, 1.0);    // saturate(distC)     // 
    _56.x = max(_78, _56.x);               // max(distC, plen * 0.125 )        distF    其实1/4 半分辨率所以 0.125
    _56.x = min(_56.x, 0.5);            // min(distF, 0.5)
    _71 = (-_56.x) + 1.0;
    _34.x = _46 ? _71 : 0.0;        // hisCoc > 0.1 ? 1 - min(distF, 0.5) : 0        blendF         dof focus的像素不混合历史数据  distF越大 越不使用呢历史数据
    _72 = _52.y || _52.x;           // 
    _72 = _52.z || _72;
    _76 = _69.y || _69.x;
    _76 = _69.z || _76;
    _72 = _76 || _72;             // 历史颜色是否超出范围 isOutR
    _76 = _20._m3 >= 0.5;               
    _72 = _76 && _72;           // _20._m3 >= 0.5 && isOutR    是否有自定义范围
    _56.x = _72 ? 0.0 : _34.x;            // 是否超出范围 ? 0 : blendF
    _56 = (_56.xxx * _64) + _60;          // lerp(originCol, hisColFinal, blendF)
    _78 = (-_56.y) + _56.x;                 // YCoCgToRGB begin    Y - Co
    _35.w = (-_56.z) + _78;                   // Y - Co - Cg   rgb.b
    vec2 _796 = _56.yz + _56.xx;            // Y + Co     Y + Cg   rgb.g
    _35 = vec4(_35.x, _796.x, _796.y, _35.w);
    _35.x = (-_56.z) + _35.y;               //Y + Co - Cg  rgb.r  YCoCgToRGB end
    _56.x = (-_35.z) + 1.0;    // 1 - rgb.g                    
    _56.x = max(_56.x, 0.001000000047497451305389404296875);   // max(1 - rgb.g, 0.001)
    _56.x = 1.0 / _56.x;
    _56 = _35.xzw * _56.xxx;                   // rgb / max(1 - rgb.g, 0.001)       //在perceptual空间操作类似 unity  PerceptualInvWeight   y = x / (1 + x)  -> y + yx = x -> x = y / (1 - y)
    vec3 _827 = max(_56, vec3(0.0));       // max(0, rgb)      finalCol
    _61 = vec4(_827.x, _827.y, _827.z, _61.w);          
    _32 = _61;                                              // finalCol            // TAA后的color
} 


// depth of field 权重按照coc radius是考虑

layout(set = 2, binding = 0) uniform sampler2D _11;   // sceneTex

layout(location = 0) in vec2 _14;              // uv
layout(location = 0) out vec4 _16;

void _46()
{
    uint _73 = 0u;
    _19.x = _7._m2 * 0.20000000298023223876953125;       // _7._m2 * 0.2     sample_radius   
    _21 = textureLod(_11, _14, 0.0);             // sceneColorCenter
    _32 = _21.xyz * vec3(20.0);           // sceneColor.rgb * 20
    _23 = _7._m0.w * _7._m0.x;                  // _7._m0.w * _7._m0.x           aspect_correction
    _34 = _32;                                  // sceneColor.rgb * 20
    _24 = 20.0;
    for (; _73 < 4u; _73++)                             // 循环4次，每次在两个相对的方向上进行采样 (总共 4 * 2 = 8 个样本点)。
    {
        _33.x = float(_73);
        _33.x *= 0.785398185253143310546875;            // loopCount * pi / 4
        _25 = sin(_33.x);
        _28.x = cos(_33.x);                 
        _28.y = _25;                                    // sample_direction
        vec2 _105 = _19.xx * _28;                       // sample_radius *  sample_direction       
        _30 = vec3(_105.x, _105.y, _30.z);              // sample_offset_uv 
        _30.z = _23 * _30.y;                            //  sample_offset_uv.y *= aspect_correction;
        _33 = _30.xz + _14;                            //  vec2 uv1 = _14 + sample_offset_uv; 
        _26 = textureLod(_11, _33, 0.0);               // sceneColor 
        _33 = (-_30.xz) + _14;
        _29 = textureLod(_11, _33, 0.0);              // seneColor1
        _35 = _21.w + (-_26.w);                           //  float coc_diff1 = center_sample.w - sample1.w; // _35 
        _35 = abs(_35) + 0.0500000007450580596923828125;    //   coc_diff1 = abs(coc_diff1) + 0.05;           1 / 0.05 = 20    
        _35 = 1.0 / _35;                                 // float weight1 = 1.0 / coc_diff1; // _35, CoC差异越小，权重越大  最大20
        _31 = (_26.xyz * vec3(_35)) + _34;                // weight1 * sceneColor +  sceneColor.rgb * 20     totalCol      
        _36 = _21.w + (-_29.w);
        _36 = abs(_36) + 0.0500000007450580596923828125;
        _36 = 1.0 / _36;
        _34 = (_29.xyz * vec3(_36)) + _31;              // weight2 * sceneColor1 + totalCol
        _35 = _36 + _35;                       // totalWeight
        _24 = _35 + _24;                     // totalWeight
    }
    _19.x = 1.0 / _24;                  //
    _19 = _19.xxx * _34;                                    // totalCol * totalWeight      resultCol
    _16 = vec4(_19.x, _19.y, _19.z, _16.w);      // resultCol
    _16.w = _21.w;          // sceneColorCenter.w
}

// 获取远景coc
//  min(1/(0.25 * 0.25 * pi), 1 / (cocRadius*cocRadius * pi))    1 / cocArea
// Next-Generation-Post-Processing-in-Call-of-Duty-Advanced-Warfare depth of field
layout(set = 2, binding = 0) uniform sampler2D _11;   // sceneTex   alpha 是coc radius   负数是近景

layout(location = 0) in vec2 _14;        // uv
layout(location = 0) out vec4 _16;

void _85()
{
    _18.x = _7._m0.x * _7._m1;              //    min_blur_radius 
    _22 = textureLod(_11, _14, 0.0);                    // sceneColorCenter
    vec2 _104 = max(_22.ww, vec2(0.0, 0.00999999977648258209228515625));
    _51 = vec3(_104.x, _104.y, _51.z);          // max(coc, float2(0, 0.01))
    vec3 _112 = _51.xxx * _22.xyz;
    _26 = vec4(_112.x, _112.y, _112.z, _26.w);    // coc.x * sceneColorCenter         // farSceneCol
    _72 = _7._m3 + (-1.0);
    _72 = (-_72) + abs(_22.w);               //abs(cocRadius)
    _72 = clamp(_72, 0.0, 1.0);            // saturate(abs(cocRadius) - (7._m3 + -1.0))   // cocAbsVal
    // saturate( pixelToSampleUnitsScale * sampleCoc – offsetCoc + 1.0 ) );
    _63 = _51.y * _51.y;                   // coc.y * coc.y
    _63 *= 3.1415927410125732421875;
    _63 = 1.0 / _63;  
    _63 = min(_63, 5.092957973480224609375);  // FarCocAreaFactor  // min(16/pi, 1 / (coc.y*coc.y * pi))   1 / (0.25 * 0.25 * pi)  类似 ppt  SampleAlpha   
    _25 = 0.0 >= _22.w;                     // 0 >= sceneColorCenter.a
    _28.x = _25 ? 0.0 : _72;              // 0 >= sceneColorCenter.a ? 0 : cocAbsVal    // farCoCAbsRadius    类似 ppt的 SpreadCmp
    _58 = (_7._m1 * _7._m0.x) + _22.w;   // sceneColorCenter.a + _7._m1 * _7._m0.x
    _58 *= 0.5;
    _58 = clamp(_58, 0.0, 1.0);       // saturate(( sceneColorCenter.a + _7._m1 * _7._m0.x) * 0.5)
    _68 = (_58 * (-2.0)) + 3.0;
    _58 *= _58;
    _73 = _58 * _68;                // smoothstep(0, 1, saturate(( sceneColorCenter.a + _7._m1 * _7._m0.x) * 0.5)) shiftCocFactor
    _58 = ((-_68) * _58) + 1.0;     // 1 - shiftCocFactor
    _68 = _28.x * _73;        // shiftCocFactor * farCoCAbsRadius
    _68 = _63 * _68;            // shiftCocFactor * farCoCAbsRadius * FarCocAreaFactor     cocFactor  类似 ppt的 DepthCmp2 * SampleAlpha * SpreadCmp
    _26.w = _51.x;            // coc.x
    _29 = _26 * vec4(_68);     // farSceneCol * cocFactor          wsceneColorCenterCoc
    _51.x = _28.x * _58;     // farCoCAbsRadius * (1 - shiftCocFactor)
    _51.x = _63 * _51.x;      // farCoCAbsRadius * (1 - shiftCocFactor) * cocAreaFactor  rcocFactor
    _26 = _51.xxxx * _26;     //  farSceneCol * rcocFactor          rwsceneColorCenterCoc
    _56 = 0.0 < _22.w;       
    _52 = float(_56);        // sceneColorCenter.a > 0
    _51.z = _72 * _52;        // (sceneColorCenter.a > 0) * cocAbsVal        farCoCAbsRadius
    _28 = _18.xx * vec2(0.4000000059604644775390625, 0.5);    // min_blur_radius * vec2(0.4, 0.5)     blurR
    _28.x = log2(_28.x);
    _28.x = ceil(_28.x);
    _55.x = uint(_28.x);
    _52 = float(_55.x);
    _52 = exp2(_52);           //将_28.x规整为2的幂的
    _28.x = 1.0 / _52;          // 1 / pow(2, ceil(blurR.x))           // rBlur
    _73 = _18.x / _7._m0.x;   // _7._m1
    _73 *= 0.5;                     // 0.5 * _7._m1 // current_lod_radius
    _30 = _7._m0.w * _7._m0.x;         // 7._m0.w * _7._m0.x
    _31 = _26;                  // rwsceneColorCenterCoc         nearColorBuffer
    _32 = _29;                      //wsceneColorCenterCoc       farColorBuffer   
    _59.y = _68;                        // cocFactor
    _59 = vec3(_51.xz.x, _59.y, _51.xz.y);  // float3(rcocFactor, cocFactor, farCoCAbsRadius)
    _33 = -_18.x;           // - blurR.x
    _55.x = 0u;
    while (true)
    {
        _67 = _55.x >= 2u;
        if (_67)
        {
            break;                          // 结束循环
        }
        _66 = int(_55.x) << 2;
        _55.y = uint(_66) + 4u;        //  stopNum   每一次迭代都会变多   4 8 
        _36 = _55.x >> 1u;
        _36 = (4294967294u * _36) + _55.x;
        _34 = float(_36);             // 
        _55.x++;                      //layer
        _60 = vec2(_55.yx);
        _38 = _31;
        _39 = _32;
        _74 = _59.x;
        _40 = _59.yz;
        _70 = _33;
        for (uint _313 = 0u; _313 < _55.y; _313++)
        {
            _69 = float(_313);
            _69 = (_34 * 0.5) + _69;            // 1
            _69 *= 3.1415927410125732421875;
            _69 /= _60.x;                   // 计算角度
            _41.x = sin(_69);
            _43.x = cos(_69);
            _43.y = _41.x;
            vec2 _348 = vec2(_73) * _43.xy;                 // vec2 sample_offset = sample_dir * current_lod_radius; 
            _41 = vec4(_348.x, _348.y, _41.z, _41.w);
            vec2 _355 = _60.yy * _41.xy;           // sample_offset * layer
            _41 = vec4(_355.x, _355.y, _41.z, _41.w);
            _41.z = _30 * _41.y;             // sample_offset.y *= aspect_correction;
            vec2 _366 = _41.xz + _14;
            _61 = vec3(_366.x, _61.y, _366.y);
            _44 = textureLod(_11, _61.xz, 0.0);         // sample1
            vec2 _377 = (-_41.xz) + _14;
            _41 = vec4(_377.x, _377.y, _41.z, _41.w);
            _42 = textureLod(_11, _41.xy, 0.0);         // sample2
            _75 = ((-_28.y) * _60.y) + abs(_44.w);
            _75 = (_75 * _28.x) + 0.5;            // float focus_weight1 = (abs(sample1.w) - layer * blurR.y) * rBlur + 0.5;   //SpreadCmp 感觉类似unity的BokehDepthOfField
            _75 = clamp(_75, 0.0, 1.0);            // focus_weight1 = clamp(focus_weight1, 0.0, 1.0); // _75
            _45 = ((-_28.y) * _60.y) + abs(_42.w);  
            _45 = (_45 * _28.x) + 0.5;         // float focus_weight2 = (abs(sample2.w) - layer * blurR.y) * rBlur + 0.5;
            _45 = clamp(_45, 0.0, 1.0);         // focus_weight2 = clamp(focus_weight2, 0.0, 1.0); // _75
            _46.w = max(_44.w, 0.0);
            _47.w = max(_42.w, 0.0);
            vec3 _430 = _44.xyz * _46.www;               
            _46 = vec4(_430.x, _430.y, _430.z, _46.w); // vec3 coc_weighted_color1 = sample1.xyz * max(sample1.w, 0.0); // _430
            vec3 _437 = _42.xyz * _47.www;           
            _47 = vec4(_437.x, _437.y, _437.z, _47.w); //vec3 coc_weighted_color2 = sample2.xyz * max(sample2.w, 0.0); // _437
            _75 = _25 ? 0.0 : _75;      // focus_weight1 = is_in_focus ? 0.0 : focus_weight1;
            _62 = _22.w + (-_70);          // 
            _62 *= 0.5;                   // (blurR + sceneColorCenter.a) * 0.5
            _62 = clamp(_62, 0.0, 1.0);     //center_coc_half = clamp(center_coc_half, 0.0, 1.0); // t
            _71 = (_62 * (-2.0)) + 3.0;
            _62 *= _62;
            _76 = _62 * _71;                 // smoothstep(0, 1, center_coc_half) center_coc_half
            _62 = ((-_71) * _62) + 1.0;
            _71 = _75 * _76;          // focus_weight1 * center_coc_half      // 这些相当于和上面同样的计算
            _48 = _63 * _71;         // FarCocAreaFactor * focus_weight1 * center_coc_half
            _41 = (_46 * vec4(_48)) + _39;          // FarCocAreaFactor * focus_weight1 * center_coc_half * coc_weighted_color1 + wsceneColorCenterCoc
            _71 = (_71 * _63) + _40.x;              // cocFactor +   FarCocAreaFactor * focus_weight1 * center_coc_half
            _75 *= _62;                   // 
            _48 = _63 * _75;             // FarCocAreaFactor * (1 - center_coc_half) * focus_weight1
            _43 = (_46 * vec4(_48)) + _38;   // rwsceneColorCenterCoc + coc_weighted_color1 * FarCocAreaFactor * (1 - center_coc_half) * focus_weight1
            _75 = (_75 * _63) + _74;          // rcocFactor + FarCocAreaFactor * focus_weight1 *  (1 - center_coc_half)
            _45 = _25 ? 0.0 : _45;       // focus_weight2 = is_in_focus ? 0.0 : focus_weight2;
            _76 = _45 * _76;            // focus_weight2 * center_coc_half
            _46.x = _63 * _76;        // FarCocAreaFactor * focus_weight2 * center_coc_half
            _39 = (_47 * _46.xxxx) + _41;    // FarCocAreaFactor * focus_weight1 * center_coc_half * coc_weighted_color1 + wsceneColorCenterCoc +  _63 * focus_weight2 * center_coc_half * coc_weighted_color2
            _40.x = (_76 * _63) + _71;      //  // cocFactor +   FarCocAreaFactor * focus_weight1 * center_coc_half + FarCocAreaFactor * focus_weight2 * center_coc_half
            _45 *= _62;
            _62 = _63 * _45;
            _38 = (_47 * vec4(_62)) + _43;     //  rcocFactor + FarCocAreaFactor * focus_weight1 *  (1 - center_coc_half) * coc_weighted_color1 + _63 * focus_weight2 *  (1 - center_coc_half) * coc_weighted_color2
            _74 = (_45 * _63) + _75;                // // rcocFactor + FarCocAreaFactor * focus_weight1 *  (1 - center_coc_half) + FarCocAreaFactor * focus_weight2 *  (1 - center_coc_half)
            _40.y = (_51.z * 2.0) + _40.y;    // ccocFactor + 2 * ccocFactor
        }
        _31 = _38;
        _32 = _39;
        _59.x = _74;
        _59 = vec3(_59.x, _40.x, _40.y);
    }
    _20 = _18.x * 1.25;           
    _18.x = max(_20, 0.00999999977648258209228515625);         // max(min_blur_radius * 1.25, 0.01)
    _18.x *= _18.x;
    _18.x *= 3.1415927410125732421875;
    _18.x = 1.0 / _18.x;
    _18.x = min(_18.x, 5.092957973480224609375);   // 
    _18.x = 1.0 / _18.x;              //curFactor              // 1 / min(16/pi, 1 / (pi * max(min_blur_radius * 1.25, 0.01) * max(min_blur_radius * 1.25, 0.01)))
    _25 = _59.y == 0.0;
    _51.x = float(_25);                            // float(cocFactor == 0)
    _18.x *= _59.x;                               // float alpha = saturate( 2.0 * ( 1.0 / SAMPLE_COUNT ) * ( 1.0 / SampleAlpha( tileMaxCoc ) ) * foreground.a );
    _18.x = (_18.x * 0.039999999105930328369140625) + _51.x;  //  0.04 * a
    _18.x = clamp(_18.x, 0.0, 1.0);         // 
    _25 = 0.001000000047497451305389404296875 < _59.y;
    _51.x = 1.0 / _59.y;
    _51.x = _25 ? _51.x : 0.0;
    _21 = _51.xxxx * _32;                         // normalized_far 
    _37 = 0.001000000047497451305389404296875 < _59.x;
    _51.x = 1.0 / _59.x;
    _51.x = _37 ? _51.x : 0.0;
    _26 = (_31 * _51.xxxx) + (-_21);
    _18 = (_18.xxxx * _26) + _21;            //  lerp(normalized_far, normalized_near, _18.x)
    _26.x = _59.z * 0.039999999105930328369140625;      // farCoCAbsRadius  * 0.04        0.04 = 1 / sampleCount  1 / 25  算alpha ， 见ppt
    _57 = _59.y + _59.x;
    _37 = 0.0 < _57;
    _26.x = _37 ? _26.x : 0.0;            // far
    _72 = max(_18.w, 0.001000000047497451305389404296875);
    vec3 _676 = _18.xyz / vec3(_72);                 //  final_color_unfixed = _18.xyz / _72
    _18 = vec4(_676.x, _676.y, _676.z, _18.w);
    vec3 _683 = _26.xxx * _18.xyz;
    _16 = vec4(_683.x, _683.y, _683.z, _16.w);
    _16.w = (-_26.x) + 1.0;
}

// 合并景深结果到scene buffer
// Blend One SrcAlpha

void _25()
{
    _15 = texture(_7, _10);
    _13 = _15;
}


// 半透pass

// hair 头发

