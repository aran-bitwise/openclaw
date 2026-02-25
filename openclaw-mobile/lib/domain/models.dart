enum EventType { humanMessage, heartbeat, cron, internalHook, agentHandoff, hook, webhook }

enum QueueState { queued, processing, completed, failed, deadLetter }

enum MissedRunPolicy { skip, catchUp }

enum CronScheduleType { daily, weekly, custom }

enum HookType { startup, turnStart, turnEnd, reset, memoryFlush }

abstract class VersionedEntity {
  int get schemaVersion;
  Map<String, dynamic> toJson();
}

class HookSettings {
  HookSettings({
    required this.enabled,
    required this.enabledHooks,
    required this.promptTemplates,
    required this.allowedEmitHooks,
    this.maxDepth = 4,
    this.maxHookEventsPerRoot = 12,
  });

  final bool enabled;
  final Map<String, bool> enabledHooks;
  final Map<String, String> promptTemplates;
  final List<String> allowedEmitHooks;
  final int maxDepth;
  final int maxHookEventsPerRoot;

  factory HookSettings.defaults() => HookSettings(
    enabled: true,
    enabledHooks: {for (final t in HookType.values) t.name: true},
    promptTemplates: {
      HookType.startup.name: 'Startup hook executed.',
      HookType.turnStart.name: 'Turn starting.',
      HookType.turnEnd.name: 'Turn complete.',
      HookType.reset.name: 'Session reset requested.',
      HookType.memoryFlush.name: 'Memory flush requested.',
    },
    allowedEmitHooks: [HookType.turnStart.name, HookType.turnEnd.name, HookType.reset.name, HookType.memoryFlush.name],
  );

  factory HookSettings.fromJson(Map<String, dynamic> json) => HookSettings(
    enabled: json['enabled'] as bool? ?? true,
    enabledHooks: Map<String, bool>.from((json['enabledHooks'] as Map?) ?? {}),
    promptTemplates: Map<String, String>.from((json['promptTemplates'] as Map?) ?? {}),
    allowedEmitHooks: List<String>.from(json['allowedEmitHooks'] as List? ?? []),
    maxDepth: json['maxDepth'] as int? ?? 4,
    maxHookEventsPerRoot: json['maxHookEventsPerRoot'] as int? ?? 12,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'enabledHooks': enabledHooks,
    'promptTemplates': promptTemplates,
    'allowedEmitHooks': allowedEmitHooks,
    'maxDepth': maxDepth,
    'maxHookEventsPerRoot': maxHookEventsPerRoot,
  };

  bool isHookEnabled(HookType type) => enabled && (enabledHooks[type.name] ?? false);

  HookSettings copyWith({
    bool? enabled,
    Map<String, bool>? enabledHooks,
    Map<String, String>? promptTemplates,
    List<String>? allowedEmitHooks,
    int? maxDepth,
    int? maxHookEventsPerRoot,
  }) {
    return HookSettings(
      enabled: enabled ?? this.enabled,
      enabledHooks: enabledHooks ?? this.enabledHooks,
      promptTemplates: promptTemplates ?? this.promptTemplates,
      allowedEmitHooks: allowedEmitHooks ?? this.allowedEmitHooks,
      maxDepth: maxDepth ?? this.maxDepth,
      maxHookEventsPerRoot: maxHookEventsPerRoot ?? this.maxHookEventsPerRoot,
    );
  }
}


class HandoffSettings {
  HandoffSettings({
    required this.enabled,
    required this.allowedTargets,
    this.requireApprovalForHighRisk = true,
    this.maxDepth = 4,
    this.maxConcurrentChains = 3,
  });

  final bool enabled;
  final List<String> allowedTargets;
  final bool requireApprovalForHighRisk;
  final int maxDepth;
  final int maxConcurrentChains;

  factory HandoffSettings.defaults() => HandoffSettings(enabled: true, allowedTargets: []);

  factory HandoffSettings.fromJson(Map<String, dynamic> json) => HandoffSettings(
    enabled: json['enabled'] as bool? ?? true,
    allowedTargets: List<String>.from(json['allowedTargets'] as List? ?? []),
    requireApprovalForHighRisk: json['requireApprovalForHighRisk'] as bool? ?? true,
    maxDepth: json['maxDepth'] as int? ?? 4,
    maxConcurrentChains: json['maxConcurrentChains'] as int? ?? 3,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'allowedTargets': allowedTargets,
    'requireApprovalForHighRisk': requireApprovalForHighRisk,
    'maxDepth': maxDepth,
    'maxConcurrentChains': maxConcurrentChains,
  };

  HandoffSettings copyWith({
    bool? enabled,
    List<String>? allowedTargets,
    bool? requireApprovalForHighRisk,
    int? maxDepth,
    int? maxConcurrentChains,
  }) {
    return HandoffSettings(
      enabled: enabled ?? this.enabled,
      allowedTargets: allowedTargets ?? this.allowedTargets,
      requireApprovalForHighRisk: requireApprovalForHighRisk ?? this.requireApprovalForHighRisk,
      maxDepth: maxDepth ?? this.maxDepth,
      maxConcurrentChains: maxConcurrentChains ?? this.maxConcurrentChains,
    );
  }
}

class ActiveHoursWindow {
  ActiveHoursWindow({required this.startMinuteOfDay, required this.endMinuteOfDay});

  final int startMinuteOfDay;
  final int endMinuteOfDay;

  factory ActiveHoursWindow.fromJson(Map<String, dynamic> json) => ActiveHoursWindow(
    startMinuteOfDay: json['startMinuteOfDay'] as int,
    endMinuteOfDay: json['endMinuteOfDay'] as int,
  );

  Map<String, dynamic> toJson() => {
    'startMinuteOfDay': startMinuteOfDay,
    'endMinuteOfDay': endMinuteOfDay,
  };
}

class HeartbeatSettings {
  HeartbeatSettings({
    required this.enabled,
    required this.intervalMinutes,
    required this.activeHours,
    required this.promptTemplate,
    this.lastFiredAt,
    this.suppressedUntil,
    this.suppressionToken = 'HEARTBEAT_OK',
    this.suppressionWindowMinutes = 120,
  });

  final bool enabled;
  final int intervalMinutes;
  final ActiveHoursWindow activeHours;
  final String promptTemplate;
  final int? lastFiredAt;
  final int? suppressedUntil;
  final String suppressionToken;
  final int suppressionWindowMinutes;

  factory HeartbeatSettings.disabled() => HeartbeatSettings(
    enabled: false,
    intervalMinutes: 30,
    activeHours: ActiveHoursWindow(startMinuteOfDay: 8 * 60, endMinuteOfDay: 21 * 60),
    promptTemplate: 'Quick status check-in. Reply HEARTBEAT_OK if no action is needed.',
  );

  factory HeartbeatSettings.fromJson(Map<String, dynamic> json) => HeartbeatSettings(
    enabled: json['enabled'] as bool? ?? false,
    intervalMinutes: json['intervalMinutes'] as int? ?? 30,
    activeHours: json['activeHours'] is Map
        ? ActiveHoursWindow.fromJson(Map<String, dynamic>.from(json['activeHours'] as Map))
        : ActiveHoursWindow(startMinuteOfDay: 8 * 60, endMinuteOfDay: 21 * 60),
    promptTemplate:
        json['promptTemplate'] as String? ?? 'Quick status check-in. Reply HEARTBEAT_OK if no action is needed.',
    lastFiredAt: json['lastFiredAt'] as int?,
    suppressedUntil: json['suppressedUntil'] as int?,
    suppressionToken: json['suppressionToken'] as String? ?? 'HEARTBEAT_OK',
    suppressionWindowMinutes: json['suppressionWindowMinutes'] as int? ?? 120,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'intervalMinutes': intervalMinutes,
    'activeHours': activeHours.toJson(),
    'promptTemplate': promptTemplate,
    'lastFiredAt': lastFiredAt,
    'suppressedUntil': suppressedUntil,
    'suppressionToken': suppressionToken,
    'suppressionWindowMinutes': suppressionWindowMinutes,
  };

  HeartbeatSettings copyWith({
    bool? enabled,
    int? intervalMinutes,
    ActiveHoursWindow? activeHours,
    String? promptTemplate,
    int? lastFiredAt,
    int? suppressedUntil,
    String? suppressionToken,
    int? suppressionWindowMinutes,
  }) {
    return HeartbeatSettings(
      enabled: enabled ?? this.enabled,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      activeHours: activeHours ?? this.activeHours,
      promptTemplate: promptTemplate ?? this.promptTemplate,
      lastFiredAt: lastFiredAt ?? this.lastFiredAt,
      suppressedUntil: suppressedUntil ?? this.suppressedUntil,
      suppressionToken: suppressionToken ?? this.suppressionToken,
      suppressionWindowMinutes: suppressionWindowMinutes ?? this.suppressionWindowMinutes,
    );
  }
}

class CronScheduleRule {
  CronScheduleRule({
    required this.type,
    this.timeOfDayMinute,
    this.weekday,
    this.everyNMinutes,
  });

  final CronScheduleType type;
  final int? timeOfDayMinute;
  final int? weekday;
  final int? everyNMinutes;

  factory CronScheduleRule.fromJson(Map<String, dynamic> json) {
    final type = CronScheduleType.values.byName(json['type'] as String);
    return CronScheduleRule(
      type: type,
      timeOfDayMinute: json['timeOfDayMinute'] as int?,
      weekday: json['weekday'] as int?,
      everyNMinutes: json['everyNMinutes'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'timeOfDayMinute': timeOfDayMinute,
    'weekday': weekday,
    'everyNMinutes': everyNMinutes,
  };
}

class CronSchedule implements VersionedEntity {
  CronSchedule({
    required this.scheduleId,
    required this.agentId,
    required this.channelId,
    required this.sessionId,
    required this.enabled,
    required this.rule,
    required this.timezoneId,
    required this.missedRunPolicy,
    required this.promptTemplate,
    this.lastRunAt,
    this.nextRunAt,
    this.schemaVersion = 1,
  });

  final String scheduleId;
  final String agentId;
  final String channelId;
  final String sessionId;
  final bool enabled;
  final CronScheduleRule rule;
  final String timezoneId;
  final MissedRunPolicy missedRunPolicy;
  final String promptTemplate;
  final int? lastRunAt;
  final int? nextRunAt;

  @override
  final int schemaVersion;

  factory CronSchedule.fromJson(Map<String, dynamic> json) => CronSchedule(
    scheduleId: json['scheduleId'] as String,
    agentId: json['agentId'] as String,
    channelId: json['channelId'] as String,
    sessionId: json['sessionId'] as String,
    enabled: json['enabled'] as bool? ?? true,
    rule: CronScheduleRule.fromJson(Map<String, dynamic>.from(json['rule'] as Map)),
    timezoneId: json['timezoneId'] as String? ?? 'local-device',
    missedRunPolicy: MissedRunPolicy.values.byName(json['missedRunPolicy'] as String? ?? 'skip'),
    promptTemplate: json['promptTemplate'] as String,
    lastRunAt: json['lastRunAt'] as int?,
    nextRunAt: json['nextRunAt'] as int?,
    schemaVersion: json['schemaVersion'] as int? ?? 1,
  );

  @override
  Map<String, dynamic> toJson() => {
    'scheduleId': scheduleId,
    'agentId': agentId,
    'channelId': channelId,
    'sessionId': sessionId,
    'enabled': enabled,
    'rule': rule.toJson(),
    'timezoneId': timezoneId,
    'missedRunPolicy': missedRunPolicy.name,
    'promptTemplate': promptTemplate,
    'lastRunAt': lastRunAt,
    'nextRunAt': nextRunAt,
    'schemaVersion': schemaVersion,
  };

  CronSchedule copyWith({
    bool? enabled,
    CronScheduleRule? rule,
    String? channelId,
    String? sessionId,
    MissedRunPolicy? missedRunPolicy,
    String? promptTemplate,
    int? lastRunAt,
    int? nextRunAt,
  }) {
    return CronSchedule(
      scheduleId: scheduleId,
      agentId: agentId,
      channelId: channelId ?? this.channelId,
      sessionId: sessionId ?? this.sessionId,
      enabled: enabled ?? this.enabled,
      rule: rule ?? this.rule,
      timezoneId: timezoneId,
      missedRunPolicy: missedRunPolicy ?? this.missedRunPolicy,
      promptTemplate: promptTemplate ?? this.promptTemplate,
      lastRunAt: lastRunAt ?? this.lastRunAt,
      nextRunAt: nextRunAt ?? this.nextRunAt,
      schemaVersion: schemaVersion,
    );
  }
}

class AgentProfile implements VersionedEntity {
  AgentProfile({
    required this.id,
    required this.name,
    required this.createdAt,
    HeartbeatSettings? heartbeat,
    HookSettings? hooks,
    HandoffSettings? handoff,
    this.schemaVersion = 4,
  }) : heartbeat = heartbeat ?? HeartbeatSettings.disabled(),
       hooks = hooks ?? HookSettings.defaults(),
       handoff = handoff ?? HandoffSettings.defaults();

  final String id;
  final String name;
  final int createdAt;
  final HeartbeatSettings heartbeat;
  final HookSettings hooks;
  final HandoffSettings handoff;
  @override
  final int schemaVersion;

  factory AgentProfile.fromJson(Map<String, dynamic> json) => AgentProfile(
    id: json['id'] as String,
    name: json['name'] as String,
    createdAt: json['createdAt'] as int,
    heartbeat: json['heartbeat'] is Map
        ? HeartbeatSettings.fromJson(Map<String, dynamic>.from(json['heartbeat'] as Map))
        : HeartbeatSettings.disabled(),
    hooks: json['hooks'] is Map
        ? HookSettings.fromJson(Map<String, dynamic>.from(json['hooks'] as Map))
        : HookSettings.defaults(),
    handoff: json['handoff'] is Map
        ? HandoffSettings.fromJson(Map<String, dynamic>.from(json['handoff'] as Map))
        : HandoffSettings.defaults(),
    schemaVersion: (json['schemaVersion'] as int?) ?? 1,
  );

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt,
    'heartbeat': heartbeat.toJson(),
    'hooks': hooks.toJson(),
    'handoff': handoff.toJson(),
    'schemaVersion': schemaVersion,
  };

  AgentProfile copyWith({String? name, HeartbeatSettings? heartbeat, HookSettings? hooks, HandoffSettings? handoff}) {
    return AgentProfile(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
      heartbeat: heartbeat ?? this.heartbeat,
      hooks: hooks ?? this.hooks,
      handoff: handoff ?? this.handoff,
      schemaVersion: schemaVersion,
    );
  }
}

class Session implements VersionedEntity {
  Session({required this.id, required this.agentId, required this.channelId, required this.createdAt, this.schemaVersion = 1});

  final String id;
  final String agentId;
  final String channelId;
  final int createdAt;
  @override
  final int schemaVersion;

  factory Session.fromJson(Map<String, dynamic> json) => Session(
    id: json['id'] as String,
    agentId: json['agentId'] as String,
    channelId: json['channelId'] as String,
    createdAt: json['createdAt'] as int,
    schemaVersion: (json['schemaVersion'] as int?) ?? 1,
  );

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'agentId': agentId,
    'channelId': channelId,
    'createdAt': createdAt,
    'schemaVersion': schemaVersion,
  };
}

class Event implements VersionedEntity {
  Event({
    required this.id,
    required this.sessionId,
    required this.type,
    required this.payload,
    required this.idempotencyKey,
    required this.createdAt,
    this.schemaVersion = 1,
  });

  final String id;
  final String sessionId;
  final EventType type;
  final Map<String, dynamic> payload;
  final String idempotencyKey;
  final int createdAt;
  @override
  final int schemaVersion;

  factory Event.fromJson(Map<String, dynamic> json) {
    final rawType = json['type'] as String;
    final normalized = rawType == 'message' ? 'humanMessage' : rawType;
    return Event(
      id: json['id'] as String,
      sessionId: json['sessionId'] as String,
      type: EventType.values.byName(normalized),
      payload: Map<String, dynamic>.from(json['payload'] as Map),
      idempotencyKey: json['idempotencyKey'] as String,
      createdAt: json['createdAt'] as int,
      schemaVersion: (json['schemaVersion'] as int?) ?? 1,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'sessionId': sessionId,
    'type': type.name,
    'payload': payload,
    'idempotencyKey': idempotencyKey,
    'createdAt': createdAt,
    'schemaVersion': schemaVersion,
  };
}

class MemoryEntry implements VersionedEntity {
  MemoryEntry({
    required this.id,
    required this.scope,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    required this.lastAccessedAt,
    this.scopeId,
    this.entryType = MemoryEntryType.fact,
    this.sourceEventId,
    this.sourceRunId,
    this.sourceAgentId,
    this.sourceSessionId,
    this.sourceHandoffTraceId,
    this.sourceRootEventId,
    this.importance = 1,
    this.pinned = false,
    this.summaryOfEntryIds = const [],
    this.schemaVersion = 2,
  });

  final String id;
  final MemoryScope scope;
  final String? scopeId;
  final MemoryEntryType entryType;
  final String content;
  final String? sourceEventId;
  final String? sourceRunId;
  final String? sourceAgentId;
  final String? sourceSessionId;
  final String? sourceHandoffTraceId;
  final String? sourceRootEventId;
  final int importance;
  final bool pinned;
  final List<String> summaryOfEntryIds;
  final int createdAt;
  final int updatedAt;
  final int lastAccessedAt;
  @override
  final int schemaVersion;

  factory MemoryEntry.fromJson(Map<String, dynamic> json) {
    final createdAt = json['createdAt'] as int;
    final legacySessionId = json['sessionId'] as String?;
    return MemoryEntry(
      id: json['id'] as String,
      scope: json['scope'] is String
          ? MemoryScope.values.byName(json['scope'] as String)
          : (legacySessionId == null ? MemoryScope.global : MemoryScope.session),
      scopeId: json['scopeId'] as String? ?? legacySessionId,
      entryType: json['entryType'] is String
          ? MemoryEntryType.values.byName(json['entryType'] as String)
          : MemoryEntryType.fact,
      content: json['content'] as String,
      sourceEventId: json['sourceEventId'] as String?,
      sourceRunId: json['sourceRunId'] as String?,
      sourceAgentId: json['sourceAgentId'] as String?,
      sourceSessionId: json['sourceSessionId'] as String? ?? legacySessionId,
      sourceHandoffTraceId: json['sourceHandoffTraceId'] as String?,
      sourceRootEventId: json['sourceRootEventId'] as String?,
      importance: json['importance'] as int? ?? 1,
      pinned: json['pinned'] as bool? ?? false,
      summaryOfEntryIds: List<String>.from(json['summaryOfEntryIds'] as List? ?? const []),
      createdAt: createdAt,
      updatedAt: json['updatedAt'] as int? ?? createdAt,
      lastAccessedAt: json['lastAccessedAt'] as int? ?? createdAt,
      schemaVersion: (json['schemaVersion'] as int?) ?? 2,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'scope': scope.name,
    'scopeId': scopeId,
    'entryType': entryType.name,
    'content': content,
    'sourceEventId': sourceEventId,
    'sourceRunId': sourceRunId,
    'sourceAgentId': sourceAgentId,
    'sourceSessionId': sourceSessionId,
    'sourceHandoffTraceId': sourceHandoffTraceId,
    'sourceRootEventId': sourceRootEventId,
    'importance': importance,
    'pinned': pinned,
    'summaryOfEntryIds': summaryOfEntryIds,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'lastAccessedAt': lastAccessedAt,
    'schemaVersion': schemaVersion,
  };

  MemoryEntry copyWith({
    String? scopeId,
    String? content,
    int? updatedAt,
    int? lastAccessedAt,
    int? importance,
    bool? pinned,
  }) {
    return MemoryEntry(
      id: id,
      scope: scope,
      scopeId: scopeId ?? this.scopeId,
      entryType: entryType,
      content: content ?? this.content,
      sourceEventId: sourceEventId,
      sourceRunId: sourceRunId,
      sourceAgentId: sourceAgentId,
      sourceSessionId: sourceSessionId,
      sourceHandoffTraceId: sourceHandoffTraceId,
      sourceRootEventId: sourceRootEventId,
      importance: importance ?? this.importance,
      pinned: pinned ?? this.pinned,
      summaryOfEntryIds: summaryOfEntryIds,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
      schemaVersion: schemaVersion,
    );
  }
}

enum MemoryScope { global, agent, session }

enum MemoryEntryType { fact, summary }

enum ToolRiskLevel { low, medium, high }

class ToolInvocation implements VersionedEntity {
  ToolInvocation({
    required this.id,
    required this.eventId,
    required this.agentId,
    required this.sessionId,
    required this.toolId,
    required this.capabilityCategory,
    required this.requiredPermissions,
    required this.riskLevel,
    required this.inputSchema,
    required this.outputSchema,
    required this.idempotencyKey,
    required this.inputRedacted,
    required this.decisionAllowed,
    required this.decisionReason,
    required this.consentOutcome,
    required this.outcome,
    required this.outputRedacted,
    required this.createdAt,
    required this.updatedAt,
    this.handoffTraceId,
    this.rootEventId,
    this.schemaVersion = 2,
  });

  final String id;
  final String eventId;
  final String agentId;
  final String sessionId;
  final String toolId;
  final String capabilityCategory;
  final List<String> requiredPermissions;
  final ToolRiskLevel riskLevel;
  final Map<String, dynamic> inputSchema;
  final Map<String, dynamic> outputSchema;
  final String idempotencyKey;
  final String inputRedacted;
  final bool decisionAllowed;
  final String decisionReason;
  final String consentOutcome;
  final String outcome;
  final String outputRedacted;
  final String? handoffTraceId;
  final String? rootEventId;
  final int createdAt;
  final int updatedAt;
  @override
  final int schemaVersion;

  factory ToolInvocation.fromJson(Map<String, dynamic> json) => ToolInvocation(
    id: json['id'] as String,
    eventId: json['eventId'] as String,
    agentId: json['agentId'] as String? ?? 'unknown-agent',
    sessionId: json['sessionId'] as String? ?? 'unknown-session',
    toolId: json['toolId'] as String? ?? (json['toolName'] as String? ?? 'unknown-tool'),
    capabilityCategory: json['capabilityCategory'] as String? ?? 'unknown',
    requiredPermissions: List<String>.from(json['requiredPermissions'] as List? ?? const []),
    riskLevel: ToolRiskLevel.values.byName(json['riskLevel'] as String? ?? 'low'),
    inputSchema: Map<String, dynamic>.from((json['inputSchema'] as Map?) ?? const {}),
    outputSchema: Map<String, dynamic>.from((json['outputSchema'] as Map?) ?? const {}),
    idempotencyKey: json['idempotencyKey'] as String? ?? 'legacy',
    inputRedacted: json['inputRedacted'] as String? ?? '',
    decisionAllowed: json['decisionAllowed'] as bool? ?? ((json['status'] as String?) == 'allowed'),
    decisionReason: json['decisionReason'] as String? ?? (json['status'] as String? ?? 'unknown'),
    consentOutcome: json['consentOutcome'] as String? ?? 'not_required',
    outcome: json['outcome'] as String? ?? (json['status'] as String? ?? 'unknown'),
    outputRedacted: json['outputRedacted'] as String? ?? '',
    handoffTraceId: json['handoffTraceId'] as String?,
    rootEventId: json['rootEventId'] as String?,
    createdAt: json['createdAt'] as int? ?? 0,
    updatedAt: json['updatedAt'] as int? ?? 0,
    schemaVersion: (json['schemaVersion'] as int?) ?? 2,
  );

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'eventId': eventId,
    'agentId': agentId,
    'sessionId': sessionId,
    'toolId': toolId,
    'capabilityCategory': capabilityCategory,
    'requiredPermissions': requiredPermissions,
    'riskLevel': riskLevel.name,
    'inputSchema': inputSchema,
    'outputSchema': outputSchema,
    'idempotencyKey': idempotencyKey,
    'inputRedacted': inputRedacted,
    'decisionAllowed': decisionAllowed,
    'decisionReason': decisionReason,
    'consentOutcome': consentOutcome,
    'outcome': outcome,
    'outputRedacted': outputRedacted,
    'handoffTraceId': handoffTraceId,
    'rootEventId': rootEventId,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'schemaVersion': schemaVersion,
  };
}

class ToolRegistration {
  const ToolRegistration({
    required this.toolId,
    required this.capabilityCategory,
    required this.requiredPermissions,
    required this.riskLevel,
    required this.inputSchema,
    required this.outputSchema,
  });

  final String toolId;
  final String capabilityCategory;
  final List<String> requiredPermissions;
  final ToolRiskLevel riskLevel;
  final Map<String, dynamic> inputSchema;
  final Map<String, dynamic> outputSchema;
}



class ToolAuditRecord {
  ToolAuditRecord({
    required this.id,
    required this.invocationId,
    required this.eventId,
    required this.agentId,
    required this.sessionId,
    required this.toolId,
    required this.decisionAllowed,
    required this.decisionReason,
    required this.consentOutcome,
    required this.outcome,
    required this.inputRedacted,
    required this.outputRedacted,
    required this.createdAt,
    this.handoffTraceId,
    this.rootEventId,
  });

  final String id;
  final String invocationId;
  final String eventId;
  final String agentId;
  final String sessionId;
  final String toolId;
  final bool decisionAllowed;
  final String decisionReason;
  final String consentOutcome;
  final String outcome;
  final String inputRedacted;
  final String outputRedacted;
  final int createdAt;
  final String? handoffTraceId;
  final String? rootEventId;
}

class RunResult implements VersionedEntity {
  RunResult({required this.id, required this.eventId, required this.output, required this.completedAt, this.schemaVersion = 1});

  final String id;
  final String eventId;
  final String output;
  final int completedAt;
  @override
  final int schemaVersion;

  factory RunResult.fromJson(Map<String, dynamic> json) => RunResult(
    id: json['id'] as String,
    eventId: json['eventId'] as String,
    output: json['output'] as String,
    completedAt: json['completedAt'] as int,
    schemaVersion: (json['schemaVersion'] as int?) ?? 1,
  );

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'eventId': eventId,
    'output': output,
    'completedAt': completedAt,
    'schemaVersion': schemaVersion,
  };
}

class TimelineItem {
  TimelineItem({required this.event, required this.state});

  final Event event;
  final QueueState state;
}
