/*
====================================================================================================

        License Terms for Academy Color Encoding System Components

        Academy Color Encoding System (ACES) software and tools are provided by the
        Academy under the following terms and conditions: A worldwide, royalty-free,
        non-exclusive right to copy, modify, create derivatives, and use, in source and
        binary forms, is hereby granted, subject to acceptance of this license.

        Copyright © 2015 Academy of Motion Picture Arts and Sciences (A.M.P.A.S.).
        Portions contributed by others as indicated. All rights reserved.

        Performance of any of the aforementioned acts indicates acceptance to be bound
        by the following terms and conditions:

        * Copies of source code, in whole or in part, must retain the above copyright
        notice, this list of conditions and the Disclaimer of Warranty.

        * Use in binary form must retain the above copyright notice, this list of
        conditions and the Disclaimer of Warranty in the documentation and/or other
        materials provided with the distribution.

        * Nothing in this license shall be deemed to grant any rights to trademarks,
        copyrights, patents, trade secrets or any other intellectual property of
        A.M.P.A.S. or any contributors, except as expressly stated herein.

        * Neither the name "A.M.P.A.S." nor the name of any other contributors to this
        software may be used to endorse or promote products derivative of or based on
        this software without express prior written permission of A.M.P.A.S. or the
        contributors, as appropriate.

        This license shall be construed pursuant to the laws of the State of
        California, and any disputes related thereto shall be subject to the
        jurisdiction of the courts therein.

        Disclaimer of Warranty: THIS SOFTWARE IS PROVIDED BY A.M.P.A.S. AND CONTRIBUTORS
        "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
        THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND
        NON-INFRINGEMENT ARE DISCLAIMED. IN NO EVENT SHALL A.M.P.A.S., OR ANY
        CONTRIBUTORS OR DISTRIBUTORS, BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
        SPECIAL, EXEMPLARY, RESITUTIONARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
        LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
        PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
        LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
        OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
        ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

        WITHOUT LIMITING THE GENERALITY OF THE FOREGOING, THE ACADEMY SPECIFICALLY
        DISCLAIMS ANY REPRESENTATIONS OR WARRANTIES WHATSOEVER RELATED TO PATENT OR
        OTHER INTELLECTUAL PROPERTY RIGHTS IN THE ACADEMY COLOR ENCODING SYSTEM, OR
        APPLICATIONS THEREOF, HELD BY PARTIES OTHER THAN A.M.P.A.S.,WHETHER DISCLOSED OR
        UNDISCLOSED.

====================================================================================================
*/

vec3 greaterThanVec3(vec3 x, vec3 y, vec3 a, vec3 b) {
    vec3 data   = vec3(0.0);
        data.x  = x.x > y.x ? a.x : b.x;
        data.y  = x.y > y.y ? a.y : b.y;
        data.z  = x.z > y.z ? a.z : b.z;

    return data;
}
vec3 smallerThanVec3(vec3 x, vec3 y, vec3 a, vec3 b) {
    vec3 data   = vec3(0.0);
        data.x  = x.x < y.x ? a.x : b.x;
        data.y  = x.y < y.y ? a.y : b.y;
        data.z  = x.z < y.z ? a.z : b.z;

    return data;
}

#define saturate(x) clamp(x, 0.0, 1.0)

float rgbSaturation(vec3 rgb) {
    float minrgb    = min3(rgb.x, rgb.y, rgb.z);
    float maxrgb    = max3(rgb.x, rgb.y, rgb.z);

    return (max(maxrgb, 1e-10) - max(minrgb, 1e-10)) / max(maxrgb, 1e-2);
}

float glowFwd(float ycIn, float glowGainIn, float glowMid) {
    if (ycIn <= 2.0 / 3.0 * glowMid) return glowGainIn;
    else if (ycIn >= 2.0 * glowMid) return 0.0;
    else return glowGainIn * (glowMid / ycIn - 0.5);
}

/* geometric hue angle calculation */
float rgbHue(vec3 rgb) {
    float hue;
    if (rgb.x == rgb.y && rgb.y == rgb.z) hue = 0.0;
    else hue = (180.0 * rcp(pi)) * atan(2.0 * rgb.x - rgb.y - rgb.z, sqrt(3.0) * (rgb.y - rgb.z));

    if (hue < 0.0) hue = hue + 360.0;

    return clamp(hue, 0.0, 360.0);
}

float rgbYC(vec3 rgb, const float ycRadweight) {
    float chroma    = sqrt(rgb.b * (rgb.b - rgb.g) + rgb.g * (rgb.g - rgb.r) + rgb.r * (rgb.r - rgb.b));

    return (rgb.b + rgb.g + rgb.r + ycRadweight * chroma) * rcp(3.0);
}
float rgbYC(vec3 rgb) {
    return rgbYC(rgb, 1.75);
}

float centerHue(float hue, float center) {
    float hueCentered = hue - center;

    if (hueCentered < -180.0) hueCentered += 360.0;
    else if (hueCentered > 180.0) hueCentered -= 360.0;

    return hueCentered;
}

float y_linVC(float y, float max, float min) {
    return (y - min) / (max - min);
}

vec3 XYZ_xyY(vec3 xyz) {
    vec3 xyY;
    float divisor   = (xyz.r + xyz.g + xyz.b);

    if (divisor == 0.0) divisor = 1e-10;
    xyY.r   = xyz.r / divisor;
    xyY.g   = xyz.g / divisor;
    xyY.b   = xyz.g;

    return xyY;
}
vec3 xyY_XYZ(vec3 xyY) {
    vec3 xyz;

    xyz.r   = xyY.x * xyY.z / max(xyY.g, 1e-10);
    xyz.g   = xyY.z;
    xyz.b   = (1.0 - xyY.x - xyY.y) * xyY.z / max(xyY.y, 1e-10);

    return xyz;
}