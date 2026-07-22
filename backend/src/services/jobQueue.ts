import { MAX_CONCURRENT_APPLY_JOBS, MAX_CONCURRENT_CLIENT_JOBS } from "../config.js";

export type JobStatus = "pending" | "running" | "completed" | "failed" | "cancelled";

export interface QueueJob<T> {
  id: string;
  data: T;
  status: JobStatus;
  result?: unknown;
  error?: string;
  onComplete?: (result: unknown) => void;
  onError?: (error: string) => void;
}

export class JobQueue<T> {
  private queue: QueueJob<T>[] = [];
  private running = 0;
  private cancelled = false;
  private readonly concurrency: number;
  private readonly processor: (data: T) => Promise<unknown>;

  constructor(concurrency: number, processor: (data: T) => Promise<unknown>) {
    this.concurrency = concurrency;
    this.processor = processor;
  }

  add(id: string, data: T, callbacks?: { onComplete?: (r: unknown) => void; onError?: (e: string) => void }) {
    this.queue.push({
      id,
      data,
      status: "pending",
      onComplete: callbacks?.onComplete,
      onError: callbacks?.onError,
    });
    void this.processNext();
  }

  cancel() {
    this.cancelled = true;
    for (const job of this.queue) {
      if (job.status === "pending") {
        job.status = "cancelled";
      }
    }
  }

  reset() {
    this.cancelled = false;
  }

  getStatus() {
    const total = this.queue.length;
    const completed = this.queue.filter((j) => j.status === "completed" || j.status === "failed" || j.status === "cancelled").length;
    const running = this.queue.filter((j) => j.status === "running").length;
    const pending = this.queue.filter((j) => j.status === "pending").length;
    const failed = this.queue.filter((j) => j.status === "failed").length;
    const cancelled = this.queue.filter((j) => j.status === "cancelled").length;

    return { total, completed, running, pending, failed, cancelled, jobs: this.queue };
  }

  private async processNext() {
    if (this.cancelled && this.running === 0) return;

    while (this.running < this.concurrency && !this.cancelled) {
      const next = this.queue.find((j) => j.status === "pending");
      if (!next) break;

      next.status = "running";
      this.running++;

      void this.processor(next.data)
        .then((result) => {
          next.status = "completed";
          next.result = result;
          next.onComplete?.(result);
        })
        .catch((error: Error) => {
          next.status = "failed";
          next.error = error.message;
          next.onError?.(error.message);
        })
        .finally(() => {
          this.running--;
          void this.processNext();
        });
    }
  }
}

let clientsQueue: JobQueue<number> | null = null;
let applyQueue: JobQueue<{ rowNumber: number; mode: "all" | "ssid" | "password" }> | null = null;

export function getClientsQueue(processor: (row: number) => Promise<unknown>) {
  if (!clientsQueue) {
    clientsQueue = new JobQueue(MAX_CONCURRENT_CLIENT_JOBS, processor);
  }
  return clientsQueue;
}

export function getApplyQueue(
  processor: (job: { rowNumber: number; mode: "all" | "ssid" | "password" }) => Promise<unknown>,
) {
  if (!applyQueue) {
    applyQueue = new JobQueue(MAX_CONCURRENT_APPLY_JOBS, processor);
  }
  return applyQueue;
}

export function resetClientsQueue() {
  clientsQueue = null;
}

export function resetApplyQueue() {
  applyQueue = null;
}
