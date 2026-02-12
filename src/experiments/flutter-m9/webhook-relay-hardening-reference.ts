import {
  ApiRelayReference,
  type RelayWebhookRequest,
} from "../flutter-relay/api-relay-reference.js";

export class WebhookRelayHardeningReference {
  constructor(
    private readonly relay: ApiRelayReference,
    private readonly maxPerDevice = 100,
  ) {}

  ingestWithPolicy(params: {
    request: RelayWebhookRequest;
    validateSignature: (request: RelayWebhookRequest) => boolean;
  }): {
    accepted: boolean;
    reason?: "unauthorized" | "duplicate" | "rate-limited";
  } {
    const queuedForDevice = this.relay
      .snapshot()
      .filter(
        (item) => item.deviceId === params.request.target.deviceId && item.status === "pending",
      ).length;

    if (queuedForDevice >= this.maxPerDevice) {
      return { accepted: false, reason: "rate-limited" };
    }

    const result = this.relay.ingestWebhook({
      request: params.request,
      validate: params.validateSignature,
    });

    if (!result.accepted) {
      return { accepted: false, reason: result.reason };
    }

    return { accepted: true };
  }
}
