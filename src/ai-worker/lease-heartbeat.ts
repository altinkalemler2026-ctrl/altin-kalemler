import type { ClaimedAiJob } from "./types.ts";
import { SupabaseAiWorker } from "./supabase-worker.ts";

export type LeaseHeartbeatOptions = {
  leaseSeconds?: number;
  heartbeatIntervalMilliseconds?: number;
};

const DEFAULT_LEASE_SECONDS = 300;
const DEFAULT_HEARTBEAT_INTERVAL_MILLISECONDS = 120_000;

export class LeaseHeartbeat {
  private readonly worker: SupabaseAiWorker;
  private readonly job: ClaimedAiJob;
  private readonly leaseSeconds: number;
  private readonly heartbeatIntervalMilliseconds: number;

  private timer: ReturnType<typeof setInterval> | null = null;
  private renewalInProgress = false;
  private stopped = false;
  private heartbeatError: Error | null = null;

  constructor(
    worker: SupabaseAiWorker,
    job: ClaimedAiJob,
    options: LeaseHeartbeatOptions = {},
  ) {
    this.worker = worker;
    this.job = job;
    this.leaseSeconds =
      options.leaseSeconds ?? DEFAULT_LEASE_SECONDS;
    this.heartbeatIntervalMilliseconds =
      options.heartbeatIntervalMilliseconds ??
      DEFAULT_HEARTBEAT_INTERVAL_MILLISECONDS;

    if (this.leaseSeconds < 30) {
      throw new Error(
        "leaseSeconds must be at least 30 seconds.",
      );
    }

    if (this.heartbeatIntervalMilliseconds <= 0) {
      throw new Error(
        "heartbeatIntervalMilliseconds must be greater than zero.",
      );
    }

    if (
      this.heartbeatIntervalMilliseconds >=
      this.leaseSeconds * 1000
    ) {
      throw new Error(
        "Heartbeat interval must be shorter than the lease duration.",
      );
    }
  }

  start(): void {
    if (this.timer) {
      throw new Error(
        "Lease heartbeat is already running.",
      );
    }

    if (this.stopped) {
      throw new Error(
        "A stopped lease heartbeat cannot be restarted.",
      );
    }

    this.timer = setInterval(() => {
      void this.renew();
    }, this.heartbeatIntervalMilliseconds);
  }

  private async renew(): Promise<void> {
    if (
      this.stopped ||
      this.renewalInProgress ||
      this.heartbeatError
    ) {
      return;
    }

    this.renewalInProgress = true;

    try {
      const result = await this.worker.renewLease(
        this.job,
        this.leaseSeconds,
      );

      console.log(
        "AI job lease yenilendi:",
        JSON.stringify(result),
      );
    } catch (error) {
      this.heartbeatError =
        error instanceof Error
          ? error
          : new Error(String(error));

      console.error(
        "AI job heartbeat hatası:",
        this.heartbeatError.message,
      );
    } finally {
      this.renewalInProgress = false;
    }
  }

  assertHealthy(): void {
    if (!this.heartbeatError) {
      return;
    }

    throw new Error(
      `AI job heartbeat failed: ${this.heartbeatError.message}`,
    );
  }

  async stop(): Promise<void> {
    this.stopped = true;

    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }

    while (this.renewalInProgress) {
      await new Promise<void>((resolve) => {
        setTimeout(resolve, 25);
      });
    }
  }
}