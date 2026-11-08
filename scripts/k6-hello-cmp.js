import http from 'k6/http';
import { check } from 'k6';

// 最小 handler 对比：两边都只回 200 + "Hello, World!"
export const options = {
    vus: 500,
    duration: '30s',
    discardResponseBodies: false,
    summaryTrendStats: ['avg', 'p(90)', 'p(95)', 'p(99)', 'max'],
    thresholds: {},
};

export default function () {
    const res = http.get(__ENV.URL);
    check(res, {
        'status is 200': (r) => r.status === 200,
        'body ok': (r) => r.body === 'Hello, World!',
    });
}
