// 느린 업스트림을 부르는 API 와, 업스트림을 전혀 안 부르는 API 를 같이 때린다.
// 풀 상한이 격리로 동작하면 뒤쪽은 멀쩡해야 한다.
import http from 'k6/http';
import { Trend, Rate } from 'k6/metrics';

const callDur = new Trend('call_duration', true);
const localDur = new Trend('local_duration', true);
const callFail = new Rate('call_failed');

export const options = {
  scenarios: {
    // 두 조건에 같은 부하를 주려면 도착률을 고정해야 한다.
    // constant-vus 로 두면 fail-fast 쪽이 훨씬 많이 쏘게 돼서 비교가 안 된다.
    slow: {
      executor: 'constant-arrival-rate',
      rate: Number(__ENV.SLOW_RATE || 100), timeUnit: '1s',
      duration: __ENV.DURATION || '30s',
      preAllocatedVUs: 300, maxVUs: 500,
      exec: 'slow',
    },
    local: {
      executor: 'constant-arrival-rate',
      rate: 20, timeUnit: '1s',
      duration: __ENV.DURATION || '30s',
      preAllocatedVUs: 50, maxVUs: 200,
      exec: 'local',
    },
  },
  summaryTrendStats: ['avg', 'p(95)'],
  discardResponseBodies: true,
};

export function slow() {
  const res = http.get(`http://caller:8080/call?delayMs=${__ENV.DELAY_MS || 3000}&mode=safe`, { timeout: '60s' });
  callDur.add(res.timings.duration);
  callFail.add(res.status !== 200);
}

export function local() {
  const res = http.get('http://caller:8080/local', { timeout: '60s' });
  localDur.add(res.timings.duration);
}
