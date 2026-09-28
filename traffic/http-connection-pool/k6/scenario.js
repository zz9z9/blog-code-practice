import http from 'k6/http';
import { check } from 'k6';

export const options = {
  vus: Number(__ENV.VUS || 50),
  duration: __ENV.DURATION || '30s',
  summaryTrendStats: ['avg', 'med', 'p(95)', 'p(99)'],
  discardResponseBodies: true,
};

const DELAY_MS = __ENV.DELAY_MS || '50';
const SIZE_BYTES = __ENV.SIZE_BYTES || '0';
const CLOSE = __ENV.CLOSE || 'false';
const MODE = __ENV.MODE || 'safe';

export default function () {
  const res = http.get(
    `http://caller:8080/call?delayMs=${DELAY_MS}&sizeBytes=${SIZE_BYTES}&close=${CLOSE}&mode=${MODE}`
  );
  check(res, { 'status 200': (r) => r.status === 200 });
}
