//
//  MP42Rational.h
//  MP42Foundation
//
//  Created by Damiano Galassi on 28/05/21.
//

#ifndef MP42Rational_h
#define MP42Rational_h

#include <stdio.h>

typedef struct MP42Rational {
    int32_t num;
    int32_t den;
} MP42Rational;

static inline MP42Rational make_rational(int32_t num, int32_t den) {
    MP42Rational r = { num, den };
    return r;
}

static inline double mp42_q2d(MP42Rational a) {
    return a.num / (double) a.den;
}

MP42Rational mp42_d2q(double d, int max);
int64_t mp42_rescale(int64_t a, int64_t b, int64_t c);

static inline int64_t mp42_rescale_q(MP42Rational q, int b)
{
    return mp42_rescale(q.num, b, q.den);
}

#endif /* MP42Rational_h */
