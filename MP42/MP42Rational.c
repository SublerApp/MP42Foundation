//
//  MP42Rational.c
//  MP42Foundation
//
//  Taken from FFmpeg AVRational

#include "MP42Rational.h"

#include <stdlib.h>
#include <math.h>
#include <limits.h>

#define FFABS(a) ((a) >= 0 ? (a) : (-(a)))
#define FFSIGN(a) ((a) > 0 ? 1 : -1)
#define FFMAX(a,b) ((a) > (b) ? (a) : (b))
#define FFMAX3(a,b,c) FFMAX(FFMAX(a,b),c)
#define FFMIN(a,b) ((a) > (b) ? (b) : (a))
#define FFMIN3(a,b,c) FFMIN(FFMIN(a,b),c)

#define FFSWAP(type,a,b) do{type SWAP_tmp= b; b= a; a= SWAP_tmp;}while(0)

int64_t mp42_gcd(int64_t a, int64_t b) {
    int za, zb, k;
    int64_t u, v;
    if (a == 0)
        return b;
    if (b == 0)
        return a;
    za = __builtin_ctzll(a);
    zb = __builtin_ctzll(b);
    k  = FFMIN(za, zb);
    u = llabs(a >> za);
    v = llabs(b >> zb);
    while (u != v) {
        if (u > v)
            FFSWAP(int64_t, v, u);
        v -= u;
        v >>= __builtin_ctzll(v);
    }
    return (uint64_t)u << k;
}

int mp42_reduce(int *dst_num, int *dst_den,
              int64_t num, int64_t den, int64_t max)
{
    MP42Rational a0 = { 0, 1 }, a1 = { 1, 0 };
    int sign = (num < 0) ^ (den < 0);
    int64_t gcd = mp42_gcd(FFABS(num), FFABS(den));

    if (gcd) {
        num = FFABS(num) / gcd;
        den = FFABS(den) / gcd;
    }
    if (num <= max && den <= max) {
        a1 = make_rational((int)num, (int)den);
        den = 0;
    }

    while (den) {
        uint64_t x        = num / den;
        int64_t next_den  = num - den * x;
        int64_t a2n       = x * a1.num + a0.num;
        int64_t a2d       = x * a1.den + a0.den;

        if (a2n > max || a2d > max) {
            if (a1.num) x =          (max - a0.num) / a1.num;
            if (a1.den) x = FFMIN(x, (max - a0.den) / a1.den);

            if (den * (2 * x * a1.den + a0.den) > num * a1.den)
                a1 = make_rational((int)(x * a1.num + a0.num),(int)(x * a1.den + a0.den));
            break;
        }

        a0  = a1;
        a1  = make_rational((int)a2n, (int)a2d);
        num = den;
        den = next_den;
    }

    *dst_num = sign ? -a1.num : a1.num;
    *dst_den = a1.den;

    return den == 0;
}

MP42Rational mp42_d2q(double d, int max)
{
    MP42Rational a;
    int exponent;
    int64_t den;
    if (isnan(d))
        return make_rational(0,0);
    if (fabs(d) > INT_MAX + 3LL)
        return make_rational(d < 0 ? -1 : 1, 0);
    frexp(d, &exponent);
    exponent = FFMAX(exponent-1, 0);
    den = 1LL << (61 - exponent);
    mp42_reduce(&a.num, &a.den, floor(d * den + 0.5), den, max);
    if ((!a.num || !a.den) && d && max>0 && max<INT_MAX)
        mp42_reduce(&a.num, &a.den, floor(d * den + 0.5), den, INT_MAX);

    return a;
}

enum MP42Rounding {
    MP42_ROUND_ZERO     = 0, ///< Round toward zero.
    MP42_ROUND_INF      = 1, ///< Round away from zero.
    MP42_ROUND_DOWN     = 2, ///< Round toward -infinity.
    MP42_ROUND_UP       = 3, ///< Round toward +infinity.
    MP42_ROUND_NEAR_INF = 5, ///< Round to nearest and halfway cases away from zero.
    MP42_ROUND_PASS_MINMAX = 8192,
};

int64_t mp42_rescale_rnd(int64_t a, int64_t b, int64_t c, enum MP42Rounding rnd)
{
    int64_t r = 0;

    if (c <= 0 || b < 0 || !((unsigned)(rnd&~MP42_ROUND_PASS_MINMAX)<=5 && (rnd&~MP42_ROUND_PASS_MINMAX)!=4))
        return INT64_MIN;

    if (rnd & MP42_ROUND_PASS_MINMAX) {
        if (a == INT64_MIN || a == INT64_MAX)
            return a;
        rnd -= MP42_ROUND_PASS_MINMAX;
    }

    if (a < 0)
        return -(uint64_t)mp42_rescale_rnd(-FFMAX(a, -INT64_MAX), b, c, rnd ^ ((rnd >> 1) & 1));

    if (rnd == MP42_ROUND_NEAR_INF)
        r = c / 2;
    else if (rnd & 1)
        r = c - 1;

    if (b <= INT_MAX && c <= INT_MAX) {
        if (a <= INT_MAX)
            return (a * b + r) / c;
        else {
            int64_t ad = a / c;
            int64_t a2 = (a % c * b + r) / c;
            if (ad >= INT32_MAX && b && ad > (INT64_MAX - a2) / b)
                return INT64_MIN;
            return ad * b + a2;
        }
    } else {
        uint64_t a0  = a & 0xFFFFFFFF;
        uint64_t a1  = a >> 32;
        uint64_t b0  = b & 0xFFFFFFFF;
        uint64_t b1  = b >> 32;
        uint64_t t1  = a0 * b1 + a1 * b0;
        uint64_t t1a = t1 << 32;
        int i;

        a0  = a0 * b0 + t1a;
        a1  = a1 * b1 + (t1 >> 32) + (a0 < t1a);
        a0 += r;
        a1 += a0 < r;

        for (i = 63; i >= 0; i--) {
            a1 += a1 + ((a0 >> i) & 1);
            t1 += t1;
            if (c <= a1) {
                a1 -= c;
                t1++;
            }
        }
        if (t1 > INT64_MAX)
            return INT64_MIN;
        return t1;
    }
}

int64_t mp42_rescale(int64_t a, int64_t b, int64_t c)
{
    return mp42_rescale_rnd(a, b, c, MP42_ROUND_NEAR_INF);
}
