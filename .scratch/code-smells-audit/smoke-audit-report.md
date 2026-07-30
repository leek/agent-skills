# Code Smells Audit — streamaba app/Services, 2026-07-30

Target: `~/Developer/Leek/streamaba/app/Services` (231 PHP files, path scope) ·
Lenses swept: 9 · Candidates: 110 · Dropped in verify: 28 · Findings: 82

Smoke-audit run of the `code-smells-audit` skill (ticket 08). Report written
here instead of the audited repo's `docs/audits/` to avoid dirtying streamaba.
Findings ranked by judged severity/leverage; taxonomy never used as a severity
proxy. Cards live at `skills/code-smells-audit/references/smells/<slug>.md`.

## 1. Duplicated Code — `app/Services/Lead/LeadWorkflowRuleEngineService.php:56-240`

- **Severity/leverage**: High — five-way engine family (Lead/Intake/Client/Staff/Authorization) multiplies every rule-engine fix by five; semantic drift in VOB logic is already live.
- **Why it qualifies**: "The expensive case is the near-copy that drifted — a missing guard, a different constant, one branch someone fixed and the rest nobody did" — handleStatusChanged/handleDocumentEvent/processScheduledRules are statement-for-statement copies of `IntakeWorkflowRuleEngineService:48-194` modulo model names, and have already drifted (`isVobIncomplete` filters Primary payers in Lead but any payer in Intake).
- **Obstruction**: Dispensables
- **Suggested refactorings**: Extract Class, Extract Method, Pull Up Method, Slide Statement, Form Template Method
- **Card**: references/smells/duplicated-code.md

## 2. Parallel Inheritance Hierarchies — `app/Services/Workflow/AbstractWorkflowRuleEngine.php:32-517`

- **Severity/leverage**: High — six coordinated class trees per workflow domain, held together only by naming discipline; every forgotten mirror is a silent hole.
- **Why it qualifies**: "Adding a subclass to one obliges you to add its mirror to the other. The tell is usually the shared prefix" — each `<Domain>WorkflowRuleEngineService` is paired by prefix with a Rule model, RoundRobin model, Execution model, Job, and Command; the `roundRobinModelClass()`/`workflowExecutionModelClass()` hooks are the card's factory "grown a line per pair".
- **Obstruction**: Change Preventers
- **Suggested refactorings**: Move Method, Move Field, Create Partial, Collapse Hierarchy
- **Card**: references/smells/parallel-inheritance-hierarchies.md

## 3. Shotgun Surgery — `app/Services/Lead/LeadWorkflowRuleEngineService.php:439-541`

- **Severity/leverage**: High — workflow-action semantics are live feature surface; guard drift between engines shows the missed-site bug has already started.
- **Why it qualifies**: "One conceptual change, many files… the same guard, format, or validation is restated in many places, so the rule has no single home" — executeCreateTask/executeChangeStatus/executeSendNotification are restated near-identically in all five engines; the duplicate-open-task guard exists in Lead but not Staff.
- **Obstruction**: Change Preventers
- **Suggested refactorings**: Extract Method, Combine Functions into Class, Combine Functions into Transform, Split Phase, Move Method, Move Field, Inline Method, Inline Class
- **Card**: references/smells/shotgun-surgery.md

## 4. Conditional Complexity — `app/Services/Client/ClientWorkflowRuleEngineService.php:339-539`

- **Severity/leverage**: High — five parallel copies of the action dispatch mean every new workflow action is a five-file shotgun edit.
- **Why it qualifies**: "What makes it a smell is… the same set of cases reappears elsewhere in the codebase" — the `match ($actionType)` at 535 is mirrored in four sibling engines plus the workflow-rule Filament resources, with default fall-throughs nobody can prove complete.
- **Obstruction**: Object Oriented Abusers
- **Suggested refactorings**: Use Guard Clauses, Extract Conditional, Replace Conditional with Polymorphism, Use Strategy Pattern, Introduce Null Object, Use Functional Programming Based Solution
- **Card**: references/smells/conditional-complexity.md

## 5. Inappropriate Static — `app/Services/Workflow/AbstractWorkflowRuleEngine.php:37-41`

- **Severity/leverage**: High — cross-instance, cross-job behavioral state in the engine that decides whether workflow rules fire; a leaked guard entry silently skips executions on long-lived queue workers.
- **Why it qualifies**: "Static state: caches, counters, memoization tables, 'current' values — that is Global Data with an access modifier" — `$recursionGuardPairs`/`$recursionGuardDepths` are static mutable maps shared across every engine instance and subclass, mutated during rule execution.
- **Obstruction**: Object Oriented Abusers
- **Suggested refactorings**: Inject Dependencies
- **Card**: references/smells/inappropriate-static.md

## 6. Duplicated Code — `app/Services/Document/DocumentDraftPdfService.php:30-84`

- **Severity/leverage**: High — a production-proven timeout fix was applied to only one copy; draft PDF jobs still carry the failure mode the sibling's comment explicitly diagnoses.
- **Why it qualifies**: "One branch someone fixed and the rest nobody did — the divergence is invisible until it produces a bug report from only one code path" — the Pdf::view → Browsershot → Storage::put → Document::create pipeline is copied from `DocumentInstancePdfService`, which moved to `waitUntilNetworkIdle(strict: false)->timeout(45)` after SQS-retry failures while the draft copy still runs the known-bad `timeout(30)`.
- **Obstruction**: Dispensables
- **Suggested refactorings**: Extract Class, Extract Method, Pull Up Method, Slide Statement, Form Template Method
- **Card**: references/smells/duplicated-code.md

## 7. Large Class — `app/Services/Ai/StreamAbaDataContextService.php:1-1285`

- **Severity/leverage**: High — it's where AI tool context goes, so every new AI tool adds a method cluster; the clusters are already cleanly separable.
- **Why it qualifies**: "Low cohesion: distinct clusters of methods each using a disjoint subset of the fields — the class is several classes sharing a namespace" — cancellation analytics, scheduling payloads, and clinical snapshot clusters serve seven public entry points across four contexts.
- **Obstruction**: Bloaters
- **Suggested refactorings**: Extract Class, Extract Subclass, Extract Interface, Extract Domain Object, Replace Data Value with Object
- **Card**: references/smells/large-class.md

## 8. Divergent Change — `app/Services/Ai/StreamAbaDataContextService.php:29-1285`

- **Severity/leverage**: High — every AI-context feature funnels edits here; each cluster is a class waiting to be extracted behind the search/snapshot facade.
- **Why it qualifies**: "One class that changes for several unrelated reasons… the class quietly accumulated two or more kinds of decision" — a clinical-data change, a cancellation-policy change, and a scheduling-schema change each edit this one file; "you can group the methods under separate headings without renaming anything" is literally satisfied.
- **Obstruction**: Change Preventers
- **Suggested refactorings**: Extract Superclass, Extract Subclass, Extract Class, Extract Method, Move Method
- **Card**: references/smells/divergent-change.md

## 9. Large Class — `app/Services/Clinical/SupervisionHoursService.php:1-1037`

- **Severity/leverage**: High — mixes pure calculation with alert-persisting side effects behind one interface; compliance rules are regulatory-driven and will keep changing.
- **Why it qualifies**: "A class that has accumulated too many fields, methods, and reasons to exist" — hours calculation, alert lifecycle writes, compliance sweeps, threshold configuration, recommendations, and a parallel client-side reporting cluster are distinct reasons to change.
- **Obstruction**: Bloaters
- **Suggested refactorings**: Extract Class, Extract Subclass, Extract Interface, Extract Domain Object, Replace Data Value with Object
- **Card**: references/smells/large-class.md

## 10. Large Class — `app/Services/Scheduling/OperationalMapService.php:1-956`

- **Severity/leverage**: High — 48 methods, four disjoint concerns; the badge/matching cluster embeds business rules that churn independently of map rendering.
- **Why it qualifies**: "The class is several classes sharing a namespace" — marker building, drive-time match ranking, preference/language/gender badge logic, and presentation are four separable classes under one vague `*Service` name.
- **Obstruction**: Bloaters
- **Suggested refactorings**: Extract Class, Extract Subclass, Extract Interface, Extract Domain Object, Replace Data Value with Object
- **Card**: references/smells/large-class.md

## 11. Long Method — `app/Services/Billing/BillingReadinessService.php:36-178`

- **Severity/leverage**: High — billing readiness gates revenue-path state transitions, and the numbered-checklist shape invites "add check #7 inline".
- **Why it qualifies**: "Banner comments partition the body into phases; each phase is an extraction waiting for a name" — the body is literally numbered `// 1.` through `// 6.`, each a self-contained checklist-item builder awaiting a method name.
- **Obstruction**: Bloaters
- **Suggested refactorings**: Extract Method, Replace Conditional with Polymorphism, Replace Method with Command, Introduce Parameter Object, Preserve the Whole Object, Split Loop
- **Card**: references/smells/long-method.md

## 12. Long Method — `app/Services/Scheduling/TravelTimeService.php:270-437`

- **Severity/leverage**: High — the mirrored blocks mean every rule change must be made twice (a divergence bug waiting), and travel-conflict rules are actively evolving.
- **Why it qualifies**: "The method contains several distinct steps or responsibilities that were never given names of their own" — two banner-comment phases are near-identical ~60-line blocks (query, coords, gap math, buffer, warning assembly) begging for one named extraction called twice.
- **Obstruction**: Bloaters
- **Suggested refactorings**: Extract Method, Replace Conditional with Polymorphism, Replace Method with Command, Introduce Parameter Object, Preserve the Whole Object, Split Loop
- **Card**: references/smells/long-method.md

## 13. Long Parameter List — `app/Services/Communication/MessageSendingService.php:89`

- **Severity/leverage**: High — central outbound-messaging chokepoint with multiple wrapper signatures re-declaring subsets of the list; every new channel option ripples through four signatures.
- **Why it qualifies**: "Call sites forced into named arguments just to stay readable — the coping mechanism marks the smell" — `send()` takes 15 parameters (11 optional, mixed channel-specific concerns), and its own internal callers must use fully named arguments.
- **Obstruction**: Bloaters
- **Suggested refactorings**: Replace Parameter with Query, Preserve the Whole Object, Introduce Parameter Object, Remove Flag Argument, Combine Functions into Class
- **Card**: references/smells/long-parameter-list.md

## 14. Data Clump — `app/Services/Scheduling/ConflictDetectionService.php:176-476`

- **Severity/leverage**: High — a TimeSlot/AppointmentWindow parameter object collapses ~8 five-arg signatures (plus the same clump exported into TravelTimeService) and gives the duplicated overlap math one home.
- **Why it qualifies**: "The same small group of values keeps travelling together — through parameter lists — without ever being given a name" — `$staffId/$clientId, $date, $startTime, $endTime, $excludeId` recurs verbatim across eight detect* methods, and the overlap rule for the group is re-implemented twice.
- **Obstruction**: Bloaters
- **Suggested refactorings**: Extract Class, Introduce Parameter Object
- **Card**: references/smells/data-clump.md

## 15. Data Clump — `app/Services/Scheduling/TravelTimeService.php:36-60`

- **Severity/leverage**: High — eight signatures carry two unnamed coordinate pairs positionally; a swapped-argument bug is invisible to the type checker.
- **Why it qualifies**: "Two or more parameters recur in the same order across several signatures, often with a shared prefix or suffix — the shared affix is the missing type name" — `lat1/lng1/lat2/lng2` and `fromLat/fromLng/toLat/toLng` recur across eight methods; getLocationCoordinates even returns the pair as a positional array.
- **Obstruction**: Bloaters
- **Suggested refactorings**: Extract Class, Introduce Parameter Object
- **Card**: references/smells/data-clump.md

## 16. Primitive Obsession — `app/Services/Scheduling/TravelTimeService.php:36-60`

- **Severity/leverage**: High (shared) — a `Coordinate` value object owning validity and Haversine distance resolves this and finding 15 in one refactor.
- **Why it qualifies**: "A concept from the domain is represented by a bare float because no one ever created the type it deserved… the same validation is written at more than one boundary because the type cannot carry it" — a geographic coordinate is four nullable floats with the four-way null-check duplicated at lines 38 and 86.
- **Obstruction**: Bloaters
- **Suggested refactorings**: Replace Data Value with Object, Extract Class, Introduce Parameter Object, Replace Array with Object, Replace Type Code with Class, Replace Type Code with State/Strategy, Move Embellishment to Decorator
- **Card**: references/smells/primitive-obsession.md

## 17. Hidden Dependencies — `app/Services/Portal/SelectedChildService.php:18-25`

- **Severity/leverage**: High — three ambient sources (container string bindings prepared by unseen middleware, an auth guard, session) drive every public method; non-HTTP contexts must reconstruct all three by ritual.
- **Why it qualifies**: "`app(Thing::class)` or `resolve(Thing::class)` called inside a method body: service location, which hides the edge the container is resolving" — getGuardian resolves the stringly-bound 'guardian' via `app()->bound()`/`resolve()` with an Auth-guard fallback, on a class with an empty constructor.
- **Obstruction**: Data Dealers
- **Suggested refactorings**: Inject Dependencies
- **Card**: references/smells/hidden-dependencies.md

## 18. Large Class — `app/Services/Scheduling/ConflictDetectionService.php:1-963`

- **Severity/leverage**: Medium-high — the theme is cohesive ("conflicts") but scheduling conflicts are core-path and every new rule type lands here; per-conflict-type detectors are the obvious seam.
- **Why it qualifies**: "Catch-all `*Service` classes that absorb every new feature in their domain because they're 'where that kind of code goes'" — each new conflict family (overlap, time-off, availability, payer enrollment, blackout, plus slot-state hashing) has been dropped in, giving 18 public entry points.
- **Obstruction**: Bloaters
- **Suggested refactorings**: Extract Class, Extract Subclass, Extract Interface, Extract Domain Object, Replace Data Value with Object
- **Card**: references/smells/large-class.md

## 19. Combinatorial Explosion — `app/Services/Scheduling/ConflictDetectionService.php:176-957`

- **Severity/leverage**: Moderate — explosion is real at the API surface (15 detect* entry points) but bodies delegate to shared cores; leverage is collapsing axes into parameters/collaborators.
- **Why it qualifies**: "Independent choices were folded into a single hierarchy so the number of methods is the product of the options rather than their sum" — the public surface spells the grid in identifiers: `detect{Staff|Client}Conflicts{,Detailed}` × `{TimeOff|StaffAvailability|PayerEnrollment}` × `{,ForStaff/ForStaffAndClients}`.
- **Obstruction**: Bloaters
- **Suggested refactorings**: Replace Inheritance with Delegation, Tease Apart Inheritance
- **Card**: references/smells/combinatorial-explosion.md

## 20. Duplicated Code — `app/Services/Scheduling/Availability/ClientAvailabilityService.php:131-235`

- **Severity/leverage**: Medium-high — the effective-date-window and priority-ordering rules are scheduling correctness rules copied 6× across two whole-class parallels; one-sided fixes will silently skew client vs staff availability.
- **Why it qualifies**: "The same statement sequence appears in two or more places, so a change to the rule means hunting down every copy" — activeRules/activeRulesForRange/activeRulesForRangeBatch are identical query pipelines to `StaffAvailabilityService:194-300` differing only in model class and foreign key.
- **Obstruction**: Dispensables
- **Suggested refactorings**: Extract Class, Extract Method, Pull Up Method, Slide Statement, Form Template Method
- **Card**: references/smells/duplicated-code.md

## 21. Long Method — `app/Services/Scheduling/DailyRouteService.php:47-191`

- **Severity/leverage**: Medium-high — four separable analyses trapped in one body, none reusable (the tight-window logic overlaps TravelTimeService's conflict detection but can't be shared as written).
- **Why it qualifies**: "You cannot summarize what the method does without 'and'" — it builds stops and totals drive time/mileage and detects backtracking and checks tight travel windows and formats presentation strings; six accumulator locals threaded through two loops.
- **Obstruction**: Bloaters
- **Suggested refactorings**: Extract Method, Replace Conditional with Polymorphism, Replace Method with Command, Introduce Parameter Object, Preserve the Whole Object, Split Loop
- **Card**: references/smells/long-method.md

## 22. Long Parameter List — `app/Services/Scheduling/TravelTimeService.php:270-281`

- **Severity/leverage**: Medium-high — swappable coordinate/time arguments are a silent-corruption risk; a parameter object also shrinks finding 12.
- **Why it qualifies**: "Adjacent parameters of the same type: call sites can swap them and nothing fails until runtime" — 10 parameters including three adjacent Carbons and adjacent `?float $newLat, $newLng`; the lat/lng/name/type quartet is a location concept never given a type.
- **Obstruction**: Bloaters
- **Suggested refactorings**: Replace Parameter with Query, Preserve the Whole Object, Introduce Parameter Object, Remove Flag Argument, Combine Functions into Class
- **Card**: references/smells/long-parameter-list.md

## 23. Divergent Change — `app/Services/Billing/AuthorizationCadenceService.php:24-690`

- **Severity/leverage**: Moderate-high — the hex-color/label block is pure presentation inside a Billing service; extracting a presenter leaves a cohesive cadence-calculation class.
- **Why it qualifies**: "A schema change edits it, a pricing-rule change edits it, a formatting change edits it — different motives, same file" — billing rules and pace math, chart geometry, and hardcoded hex palettes/labels live in one class.
- **Obstruction**: Change Preventers
- **Suggested refactorings**: Extract Superclass, Extract Subclass, Extract Class, Extract Method, Move Method
- **Card**: references/smells/divergent-change.md

## 24. Inappropriate Static — `app/Services/Insurance/InsuranceCardParserService.php:55-177`

- **Severity/leverage**: Moderate-high — effectful IO behind static entry points in an intake-critical flow; converting to instance methods on the already-resolved service is cheap.
- **Why it qualifies**: "The test for a caller can only be written by monkey-patching or it silently hits the real clock, filesystem, or network because there was no seam to interpose" — materializeUploadedFile and the static resolution helpers perform tempfile writes, S3 reads, and logging, invoked statically from Livewire while the same class is container-resolved for parsing.
- **Obstruction**: Object Oriented Abusers
- **Suggested refactorings**: Inject Dependencies
- **Card**: references/smells/inappropriate-static.md

## 25. Afraid To Fail — `app/Services/Insurance/InsuranceCardParserService.php:302-330`

- **Severity/leverage**: Moderate — four drifting success-check copies today; a domain exception caught once at the UI edge removes them all.
- **Why it qualifies**: "Code that refuses to admit failure, handing back a status code… that the caller is expected to remember to inspect — every call site grows the same defensive if" — parse() catches Throwable and returns `['success' => bool, …]`; all four call sites repeat `if (! $result['success'] || ! $result['data'])`.
- **Obstruction**: Couplers
- **Suggested refactorings**: Move Method
- **Card**: references/smells/afraid-to-fail.md

## 26. Dubious Abstraction — `app/Services/Insurance/InsuranceCardParserService.php:211-418`

- **Severity/leverage**: Moderate — the AI-parsing core is reusable; the Filament form-filling and image-IO layers baked into it must be prised out before parsing can be reused outside forms.
- **Why it qualifies**: "A unit whose body swings between levels of abstraction… when a method named for a business step also carries the plumbing for one of those steps" — parseAndFillFormFields sequences resolve → parse → fill yet inlines Filament Notification construction, Imagick blob orientation, and raw file IO beside its domain calls.
- **Obstruction**: Change Preventers
- **Suggested refactorings**: Extract Superclass, Extract Subclass, Extract Class
- **Card**: references/smells/dubious-abstraction.md

## 27. Flag Argument — `app/Services/Insurance/InsuranceCardParserService.php:302-375`

- **Severity/leverage**: Moderate — two image-source strategies stapled behind one signature; a small ImageSource seam removes the threading.
- **Why it qualifies**: "A boolean parameter that selects which of two behaviours the callee performs puts the decision on the wrong side of the call" — readImageSource/writeImageSource branch entirely on `if ($local)`, and the flag is threaded untouched through two intermediaries; the call site is the card's named-argument patch: `parse(..., local: true)`.
- **Obstruction**: Change Preventers
- **Suggested refactorings**: Remove Flag Argument, Extract Method
- **Card**: references/smells/flag-argument.md

## 28. Dubious Abstraction — `app/Services/Scheduling/AppointmentExportService.php:14-21`

- **Severity/leverage**: Moderate — one-line smell repeated across 7 services (verified: AppointmentExport, RecurringAppointmentValidation, CalendarColor, ConflictDetection, SchedulePrint, DocumentationSettings, QuietHours); injecting the Company at the boundary fixes the family and unlocks non-panel reuse.
- **Why it qualifies**: "A mechanism baked into the wrong layer has to be prised out before anything can vary" — a scheduling-domain service's constructor resolves company context via `filament()->getTenant()`, UI-panel plumbing that blocks queue/console/API use.
- **Obstruction**: Change Preventers
- **Suggested refactorings**: Extract Superclass, Extract Subclass, Extract Class
- **Card**: references/smells/dubious-abstraction.md

## 29. Required Setup or Teardown Code — `app/Services/LeadSyncService.php:161-386`

- **Severity/leverage**: Moderate — the page-per-job chain genuinely spans processes; leverage is moving the guard/adopt/finalize protocol into one chain-owning seam instead of the job's folklore.
- **Why it qualifies**: "Documentation instructs callers what to call before and after" — startSyncLog()'s docblock literally instructs callers to guard starts with a lock + probe; SyncLeadsJob carries ~90 lines of ceremony, and a killed worker leaves logs `running` forever (which forced a dedicated reaper).
- **Obstruction**: Bloaters
- **Suggested refactorings**: Replace Constructor with Factory Method, Introduce Parameter Object
- **Card**: references/smells/required-setup-or-teardown-code.md

## 30. Conditional Complexity — `app/Services/Reporting/CohortComparisonService.php:136-421`

- **Severity/leverage**: Moderate — leverage is in the two string dispatches; the match(true) range ladders alone would not qualify (threshold banding, not type dispatch).
- **Why it qualifies**: "An if/elseif cascade or switch that dispatches on a type code, and grows a branch every time the product grows a feature" — buildCohorts and calculateMetric dispatch on dimension/metric strings with silent `default => []`/`0` fall-throughs; the same string sets reappear in CohortComparisonDashboard.
- **Obstruction**: Object Oriented Abusers
- **Suggested refactorings**: Use Guard Clauses, Extract Conditional, Replace Conditional with Polymorphism, Use Strategy Pattern, Introduce Null Object, Use Functional Programming Based Solution
- **Card**: references/smells/conditional-complexity.md

## 31. Conditional Complexity — `app/Services/Staff/CaseloadPlannerService.php:328-337`

- **Severity/leverage**: Moderate — survives on the `$change['kind']` chain only; the feasibility ladder is classification over computed data and would not qualify alone.
- **Why it qualifies**: "The same set of cases is switched on in more than one place — a new variant means editing all of them, and forgetting one is silent" — the kind set ('assign'/'reassign'/'unassign'/'discharge'/'ackDrift') is branched in applyPendingChanges and again three times in CaseloadPlannerChangeService.
- **Obstruction**: Object Oriented Abusers
- **Suggested refactorings**: Use Guard Clauses, Extract Conditional, Replace Conditional with Polymorphism, Use Strategy Pattern, Introduce Null Object, Use Functional Programming Based Solution
- **Card**: references/smells/conditional-complexity.md

## 32. Oddball Solution — `app/Services/Clinical/SessionDataValidationService.php:126-190`

- **Severity/leverage**: Medium — a clinical signing gate with two non-agreeing enforcement points; tightening the rule in one path leaves the other as a bypass.
- **Why it qualifies**: "One problem solved two different ways in two parts of the same project… neither variant is authoritative" — the `require_data_before_signing` rule is enforced here and re-enforced in `DataEntryValidationService::validateSessionData` with a different return shape, and they disagree when the setting is unset.
- **Obstruction**: Bloaters
- **Suggested refactorings**: Unify Interfaces with Adapter
- **Card**: references/smells/oddball-solution.md

## 33. Alternative Classes with Different Interfaces — `app/Services/Communication/MessageSendingService.php:73-229`

- **Severity/leverage**: Medium — a third social provider adds another composer branch instead of an implementation; the unified send() precedent exists in the same namespace.
- **Why it qualifies**: "Each class names its methods after the concrete type they live on… code must know which class it is holding before it knows which method to call" — SocialMessageSendingService exposes sendGohighLevel()/sendMeta() instead of the send(channel) contract, and InteractsWithConversationReplies:147-161 branches on a provider tag to pick the spelling.
- **Obstruction**: Object Oriented Abusers
- **Suggested refactorings**: Move Method
- **Card**: references/smells/alternative-classes-with-different-interfaces.md

## 34. Null Check — `app/Services/Cms1500PdfService.php:105-153`

- **Severity/leverage**: Moderate — a claim-form view model (or `withDefault()` on the relations) resolves absence once at the boundary instead of literal-by-literal in the export.
- **Why it qualifies**: "The absence of a value leaks out of the object that produced it and becomes everyone else's problem" — ~25 field reads each re-implement `?? ''` / `?->` on person/payer/clientPayer, with absence expressed inconsistently across adjacent lines.
- **Obstruction**: Bloaters
- **Suggested refactorings**: Introduce Null Object, Introduce Optional
- **Card**: references/smells/null-check.md

## 35. Null Check — `app/Services/Scheduling/TravelTimeService.php:38,86`

- **Severity/leverage**: Moderate — a Coordinates value object collapses the guards and stops `?int` leaking through the whole travel stack.
- **Why it qualifies**: "The same check reappears at every call site, so one design gap turns into scattered Duplicated Code" — the identical four-way coordinate guard sits at 38 and 86, and the `?float`/`?int` returns make callers at four sites re-branch.
- **Obstruction**: Bloaters
- **Suggested refactorings**: Introduce Null Object, Introduce Optional
- **Card**: references/smells/null-check.md

## 36. Special Case — `app/Services/Scheduling/CalendarAgendaEventService.php:215-230`

- **Severity/leverage**: Moderate — the OR-composition is subtle (it only excludes authorizations whose every line is 97151), exactly the kind of unnamed exception that gets mis-edited.
- **Why it qualifies**: "A routine that does one job carries a branch for 'the one weird case' — something specific rather than categorical" — the general authorization-expiration query carries an inline whereDoesntHave/orWhereHas clause keyed to the hardcoded magic string '97151'.
- **Obstruction**: Change Preventers
- **Suggested refactorings**: Consolidate Conditional Expression, Replace Conditional with Polymorphism, Introduce Null Object, Replace Exception with Test
- **Card**: references/smells/special-case.md

## 37. Message Chain — `app/Services/Clinical/SignatureRequirementService.php:74`

- **Severity/leverage**: Moderate — any restructure of the authorization graph currently breaks a clinical-signature service; `Session::payerId()` would localise the schema knowledge.
- **Why it qualifies**: "A caller that needs something from a distant object walks there hop by hop" — four relationship hops (`session->authorizationLine->authorization->clientPayer->payer_id`), with a stacked-nullsafe twin of the same walk on the line above.
- **Obstruction**: Data Dealers
- **Suggested refactorings**: Hide Delegate, Extract Method, Move Method
- **Card**: references/smells/message-chain.md

## 38. Middle Man — `app/Services/Scheduling/AvailabilityService.php:14-121`

- **Severity/leverage**: Moderate — every method added to the three delegate services must be mirrored here; callers could be repointed mechanically, keeping only the two methods with behaviour.
- **Why it qualifies**: "Once half of a class's methods are one-line delegations, the class has stopped earning its keep" — 8 of 10 public methods are single-line forwards adding no guard, mapping, or improved name; two are self-documented as compatibility shims.
- **Obstruction**: Data Dealers
- **Suggested refactorings**: Remove Middle Man, Inline Method, Replace Delegation with Inheritance, Replace Superclass with Delegate
- **Card**: references/smells/middle-man.md

## 39. Fallacious Method Name — `app/Services/Clinical/GeneralizationProgressService.php:445`

- **Severity/leverage**: Medium — every caller reading isReadyForMaintenance() as a predicate (a non-empty array is always truthy) ships a bug.
- **Why it qualifies**: "An is/has/can prefix on a method whose return type is not boolean" — `isReadyForMaintenance(GoalTarget $goalTarget): array` returns a report structure; the name promises yes/no.
- **Obstruction**: Lexical Abusers
- **Suggested refactorings**: Rename Method
- **Card**: references/smells/fallacious-method-name.md

## 40. "What" Comment — `app/Services/Scheduling/CredentialValidationService.php:33-67`

- **Severity/leverage**: Medium — a long method held together by phase banners; the banners name the private methods waiting to be extracted.
- **Why it qualifies**: "The comment paraphrases the statement below it. Delete it and nothing is lost that a better name could not carry" — "// Get staff's credentials" above `$providerProfile->credentials()->get()` restates mechanics verbatim.
- **Obstruction**: Dispensables
- **Suggested refactorings**: Extract Method, Rename Method, Introduce Assertion
- **Card**: references/smells/what-comment.md

## 41. Complicated Regex Expression — `app/Services/Document/PdfFormFieldExtractor.php:379`

- **Severity/leverage**: Medium — three intra-file copies of an invented, non-standard pattern; a fix to escape handling in one copy silently misses the others.
- **Why it qualifies**: "Writing a genuinely necessary pattern as one squeezed literal instead of composing it from named parts… the same pattern literal duplicated across files, each copy free to be fixed independently" — the PDF-name alternation pattern is retyped at :380, :396, and :519 with no shared constant.
- **Obstruction**: Obfuscators
- **Suggested refactorings**: Extract Method, Extract Variable
- **Card**: references/smells/complicated-regex-expression.md

## 42. Magic Number — `app/Services/Scheduling/UnitCalculationService.php:71`

- **Severity/leverage**: Medium — CMS 8-minute-rule constants are load-bearing billing logic; the derived `7` is the kind of digit a maintainer edits wrong.
- **Why it qualifies**: "A comment next to the number explaining what it is — the comment is the name the constant should have carried" — the block comment explains `floor(($minutes + 7) / 15)` in prose that `MINUTES_PER_UNIT` and `MINIMUM_BILLABLE_MINUTES` constants would carry in code.
- **Obstruction**: Lexical Abusers
- **Suggested refactorings**: Replace with Symbolic Constant, Replace with Parameter
- **Card**: references/smells/magic-number.md

## 43. Magic Number — `app/Services/Geocoding/CareLocationPlaceResolver.php:498`

- **Severity/leverage**: Medium leverage — the fix is one named constant, but the real payoff is that four hand-rolled haversines with three different radius spellings point at a shared distance helper.
- **Why it qualifies**: "The value's unit is not recoverable from the surrounding code… the same literal typed in more than one place with no shared declaration" — bare `6371000` carries no unit hint while siblings name theirs (`$earthRadius = 3959`, `$earthRadiusMiles = 3958.8`) and have already drifted.
- **Obstruction**: Lexical Abusers
- **Suggested refactorings**: Replace with Symbolic Constant, Replace with Parameter
- **Card**: references/smells/magic-number.md

## 44. Long Method — `app/Services/Billing/Edi835ParserService.php:20-202`

- **Severity/leverage**: Medium — squarely meets the definition (183 lines, duplicated inline finalization) but parsers are write-once/read-rarely; blast radius contained to ERA ingestion.
- **Why it qualifies**: "Banner comments partition the body into phases; each phase is an extraction waiting for a name" — every switch case carries a banner comment, and the claim/line finalization state machine is duplicated inline across the CLP, SVC, and SE cases.
- **Obstruction**: Bloaters
- **Suggested refactorings**: Extract Method, Replace Conditional with Polymorphism, Replace Method with Command, Introduce Parameter Object, Preserve the Whole Object, Split Loop
- **Card**: references/smells/long-method.md

## 45. Long Method — `app/Services/Ai/StreamAbaDataContextService.php:117-264`

- **Severity/leverage**: Medium — much of the bulk is declarative field mapping, but the duplicated session query and half-extracted mapper pattern show the phases already want names.
- **Why it qualifies**: "Blank-line 'paragraphs' partition the body into phases; each phase is an extraction waiting for a name" — load/map/assemble phases with inline mapper closures that are unnamed peers of the already-extracted targetSnapshot(); the sessions query is silently rebuilt a second time for the count.
- **Obstruction**: Bloaters
- **Suggested refactorings**: Extract Method, Replace Conditional with Polymorphism, Replace Method with Command, Introduce Parameter Object, Preserve the Whole Object, Split Loop
- **Card**: references/smells/long-method.md

## 46. Data Clump — `app/Services/Scheduling/AvailabilityService.php:25-117`

- **Severity/leverage**: Moderate — the codebase already has `AvailabilityWindow` as a return type but never accepts it as a parameter; the positional forwarding (`$start, $start, $end`) is exactly the drift nothing enforces.
- **Why it qualifies**: "Two or more parameters recur in the same order across several signatures, often with a shared prefix or suffix (startDate/endDate)" — the card's literal exemplar, forwarded positionally into both delegate services which repeat the clump.
- **Obstruction**: Bloaters
- **Suggested refactorings**: Extract Class, Introduce Parameter Object
- **Card**: references/smells/data-clump.md

## 47. Hidden Dependencies — `app/Services/Clinical/SmartDefaultsService.php:17-20`

- **Severity/leverage**: Moderate — in a queued job or Artisan command the user is null and last-used defaults silently vanish; injecting the user makes the divergence visible.
- **Why it qualifies**: "A class that quietly fetches what it needs — from the global scope, a container, a static factory, the environment — instead of being given it. The constructor takes nothing, so the object looks free to create" — the zero-argument constructor silently pulls `Auth::user()`.
- **Obstruction**: Data Dealers
- **Suggested refactorings**: Inject Dependencies
- **Card**: references/smells/hidden-dependencies.md

## 48. Hidden Dependencies — `app/Services/Privacy/HipaaMode.php:43-93`

- **Severity/leverage**: Moderate — who may enable HIPAA mode is a function of environment, config, and session, none of which appear in any signature; the swallowed-exception fallback silently reports "disabled" in queue/CLI contexts.
- **Why it qualifies**: "`env()` or `config()` read deep inside a class instead of config values being injected at construction" — config and session are read inline at seven sites, and the `catch (Throwable) => false` around `session()->get()` is the card's runtime-error confession made literal.
- **Obstruction**: Data Dealers
- **Suggested refactorings**: Inject Dependencies
- **Card**: references/smells/hidden-dependencies.md

## 49. Temporary Field — `app/Services/Clinical/SmartDefaultsService.php:13-42`

- **Severity/leverage**: Moderate — `getDefaults(Session $session)` as a parameter removes the field, the guard, and the silent-empty-array failure mode in one move.
- **Why it qualifies**: "A field that matters during one operation… populated by one method purely so another can read it" — `$session` is null until the fluent forSession() writes it solely so getDefaults() can read it; the card's Laravel heuristic ("Service classes stashing per-invocation data in properties") verbatim.
- **Obstruction**: Object Oriented Abusers
- **Suggested refactorings**: Introduce Null Object, Extract Class, Move Method
- **Card**: references/smells/temporary-field.md

## 50. Speculative Generality — `app/Services/UserPresence/NullUserPresenceBroadcaster.php:11-14`

- **Severity/leverage**: Moderate — contract + config key + env var + binding closure + null object is five artifacts of ceremony for a hook nothing uses.
- **Why it qualifies**: "Machinery built for a requirement that never arrived: an extension point with no extensions" — the config-driven driver slot exists so a real broadcaster could be swapped in, and the only concrete implementation in the app is this no-op.
- **Obstruction**: Dispensables
- **Suggested refactorings**: Collapse Hierarchy, Inline Method, Inline Class, Rename Method
- **Card**: references/smells/speculative-generality.md

## 51. Status Variable — `app/Services/Scheduling/CalendarExportService.php:242-282`

- **Severity/leverage**: Moderate — two interacting flags plus break plus fallback branch is the card's worst shape; a first-match rewrite also makes the no-transition case explicit.
- **Why it qualifies**: "A mutable primitive declared before an operation, written to during it, and read afterwards as a switch" — `$hasStandard`/`$hasDaylight` are initialised false, assigned inside branches, checked mid-loop for break and again after.
- **Obstruction**: Obfuscators
- **Suggested refactorings**: Replace with Built-In, Extract Method, Remove Status Variables
- **Card**: references/smells/status-variable.md

## 52. Status Variable — `app/Services/Scheduling/CredentialValidationService.php:60-95`

- **Severity/leverage**: Moderate — the flag plus twin negated branches make the three outcomes (valid / all-expired / missing) hard to read in compliance-relevant validation.
- **Why it qualifies**: "`$found = false;` inside a foreach where `collect($rows)->contains()` answers directly" — `$hasAnyRequired` is accumulated across the foreach and branched on twice.
- **Obstruction**: Obfuscators
- **Suggested refactorings**: Replace with Built-In, Extract Method, Remove Status Variables
- **Card**: references/smells/status-variable.md

## 53. Imperative Loops — `app/Services/Scheduling/TravelTimeService.php:503-520`

- **Severity/leverage**: Moderate readability payoff — the guard stack buries the actual travel-block computation; `sliding(2)` plus a named predicate would surface it.
- **Why it qualifies**: "An explicit integer counter used only to subscript the collection… one loop doing three jobs" — `$i` exists only for `$dayAppts[$i]`/`$dayAppts[$i + 1]`, and five manual continue guards do the filtering a pipeline would name.
- **Obstruction**: Functional Abusers
- **Suggested refactorings**: Replace Loop with Pipeline, Replace with Built-In
- **Card**: references/smells/imperative-loops.md

## 54. Side Effects — `app/Services/Portal/SelectedChildService.php:40-78`

- **Severity/leverage**: Low-moderate — the hidden auto-select is a real decision made during a read; an explicit selectDefaultChild() keeps the getter honest.
- **Why it qualifies**: "A method named like a setter, getter, or question also writes, notifies, or mutates state its name never mentions" — getSelectedChildId() performs Session::put on two paths and silently makes the selection inside a getter.
- **Obstruction**: Functional Abusers
- **Suggested refactorings**: Extract Method, Extract Field
- **Card**: references/smells/side-effects.md

## 55. Insider Trading — `app/Services/Portal/SelectedChildService.php:145-155`

- **Severity/leverage**: Low-moderate — any notification-prefs migration or full-overwrite save silently destroys portal selection; Move Field to its own column is a small, clean fix.
- **Why it qualifies**: "Each one reaches past the other's public surface into data and implementation details it was never meant to see" — persistToGuardian() writes portal navigation state into the guardian's `notification_preferences` JSON, a blob owned by the notifications feature.
- **Obstruction**: Data Dealers
- **Suggested refactorings**: Move Method, Move Field, Encapsulate Field, Replace Inheritance with Delegation, Change Bidirectional Association to Unidirectional
- **Card**: references/smells/insider-trading.md

## 56. Required Setup or Teardown Code — `app/Services/DataMigration/MigrationState.php:24-57`

- **Severity/leverage**: Low-moderate — the failure mode (silently lost migration checkpoints) surfaces far from the missed call; a named constructor that loads closes the gap cheaply.
- **Why it qualifies**: "Constructing the object leaves it unusable until a second init() call lands" — `new MigrationState(...)` leaves the typed `$data` property uninitialized so every method fatals until load(); "Call flush() to persist" is the card's caller-instruction tell.
- **Obstruction**: Bloaters
- **Suggested refactorings**: Replace Constructor with Factory Method, Introduce Parameter Object
- **Card**: references/smells/required-setup-or-teardown-code.md

## 57. Message Chain — `app/Services/Staff/CaseloadDistributionService.php:413`

- **Severity/leverage**: Low-moderate — an `isEnrolledWithPayer($payerId)` on the care-team member collapses the walk and the mirrored with() path.
- **Why it qualifies**: "Every link in the chain is a dependency the caller never asked for — it knows the shape of the whole relationship graph" — `$assignedBcba->user->person->staffProfile->activePayerEnrollments`, with the eager-load string restating the same graph a second time.
- **Obstruction**: Data Dealers
- **Suggested refactorings**: Hide Delegate, Extract Method, Move Method
- **Card**: references/smells/message-chain.md

## 58. Complicated Boolean Expression — `app/Services/LeadSyncService.php:107`

- **Severity/leverage**: Low-moderate — operands are well-named locals; naming the whole invariant is a five-minute fix.
- **Why it qualifies**: "Stack up a few negations and the reader stops asking 'what rule is this?' and starts doing discrete maths" — three negations in one pagination condition, including `! filled($pageToken)` where name and operator each carry a polarity.
- **Obstruction**: Obfuscators
- **Suggested refactorings**: Extract Method, Extract Variable, Use Guard Clauses, Simplify Conditional
- **Card**: references/smells/complicated-boolean-expression.md

## 59. Complicated Boolean Expression — `app/Services/Scheduling/OperationalMapService.php:914-927`

- **Severity/leverage**: Low-moderate — one `isSeparated()` predicate collapses both twins and removes the sync hazard between them.
- **Why it qualifies**: "A condition that has to be evaluated rather than read… lean on operator precedence" — `! ($staff->staffStatus?->is_separated ?? false)` is a negation wrapping a nullsafe-coalesce, duplicated in mirrored positive/negated form.
- **Obstruction**: Obfuscators
- **Suggested refactorings**: Extract Method, Extract Variable, Use Guard Clauses, Simplify Conditional
- **Card**: references/smells/complicated-boolean-expression.md

## 60. Status Variable — `app/Services/Scheduling/DailyRouteService.php:64-106`

- **Severity/leverage**: Low-moderate — deriving it from `$suggestions` after the loop removes one mutable from an already many-jobbed loop.
- **Why it qualifies**: "A flag surviving past the block that computed it — returned alongside the real value" — `$hasBacktracking` is mutated across iterations and returned as `has_backtracking` while it only ever mirrors whether `$suggestions` contains a backtracking entry.
- **Obstruction**: Obfuscators
- **Suggested refactorings**: Replace with Built-In, Extract Method, Remove Status Variables
- **Card**: references/smells/status-variable.md

## 61. Duplicated Code — `app/Services/Geocoding/ZipCodeAddressEnrichmentService.php:10-23`

- **Severity/leverage**: Low-medium — the negative-cache contract (SOURCE_GOOGLE_MISS) is a subtle rule that will drift silently; enrichment should call a cached-only method on ZipCodeLookupService.
- **Why it qualifies**: "The same knowledge expressed in more than one place" — the private normalize() is byte-identical in both classes, and lookupCached re-states ZipCodeLookupService's cache semantics minus the Google fallback.
- **Obstruction**: Dispensables
- **Suggested refactorings**: Extract Class, Extract Method, Pull Up Method, Slide Statement, Form Template Method
- **Card**: references/smells/duplicated-code.md

## 62. Boolean Blindness — `app/Services/Insurance/InsuranceCardImageService.php:90`

- **Severity/leverage**: Low-medium — owned code, so fully fixable: a named argument is the cheap patch, a ProcessingMode enum the card-shaped one.
- **Why it qualifies**: "Call sites that read f($x, true) where the literal's meaning is unrecoverable without opening the callee" — `processImageBlob($contents, false)` gives no hint the false is `bool $force`.
- **Obstruction**: Lexical Abusers
- **Suggested refactorings**: Introduce New Type
- **Card**: references/smells/boolean-blindness.md

## 63. Binary Operator in Name — `app/Services/Geocoding/CareLocationPlaceResolver.php:65`

- **Severity/leverage**: Low-medium — the `bool $force` parameter compounds it, but the composition is a thin, honest convenience wrapper.
- **Why it qualifies**: "An 'and' says the body has two halves that could each stand alone and be called separately" — resolve() and apply() exist as standalone public methods; resolveAndApply bundles them plus a flag guard.
- **Obstruction**: Couplers
- **Suggested refactorings**: Extract Method
- **Card**: references/smells/binary-operator-in-name.md

## 64. Dead Code — `app/Services/Scheduling/AvailabilityService.php:72-89`

- **Severity/leverage**: Low effort, real leverage — the comment actively misleads readers into believing external callers exist; safe two-minute deletion.
- **Why it qualifies**: "A way of working was replaced and the old path was never removed… exported symbols nobody imports" — both methods have zero call sites in app, tests, or views, and "Kept for compatibility with older matching callers" names callers that no longer exist.
- **Obstruction**: Dispensables
- **Suggested refactorings**: Remove It
- **Card**: references/smells/dead-code.md

## 65. Dead Code — `app/Services/Scheduling/UnitCalculationService.php:129-132`

- **Severity/leverage**: Trivial to remove; main cost is the false suggestion that payer-specific unit logic exists separately.
- **Why it qualifies**: "Exported symbols nobody imports" — calculateUnitsByPayer has no callers anywhere and is a pure pass-through to calculateUnits.
- **Obstruction**: Dispensables
- **Suggested refactorings**: Remove It
- **Card**: references/smells/dead-code.md

## 66. "What" Comment — `app/Services/Scheduling/ProviderMatchingService.php:68-74`

- **Severity/leverage**: Low — pure deletions; the code beneath already carries the names, so drift risk is the only cost.
- **Why it qualifies**: "The comment paraphrases the statement below it" — "// Get assigned provider IDs for this client" sits directly above `$assignedStaffIds = $this->getAssignedProviderIds($clientProfile, ...)`.
- **Obstruction**: Dispensables
- **Suggested refactorings**: Extract Method, Rename Method, Introduce Assertion
- **Card**: references/smells/what-comment.md

## 67. Inconsistent Names — `app/Services/Communication/ConsentService.php:76`

- **Severity/leverage**: Low — the crisp inconsistency is getOrCreate vs findOrCreate for the same exact-lookup-or-create op; the match* variants do genuine fuzzy matching.
- **Why it qualifies**: "Sibling types performing the same operation under synonyms… finding a behavior requires trying several synonyms" — one lookup-or-create lifecycle wears three verbs across four services while Eloquent's firstOrCreate already pins the vocabulary.
- **Obstruction**: Lexical Abusers
- **Suggested refactorings**: Rename Method
- **Card**: references/smells/inconsistent-names.md

## 68. Magic Number — `app/Services/Scheduling/CredentialValidationService.php:100`

- **Severity/leverage**: Low — single occurrence, single call site; one EXPIRING_SOON_DAYS constant closes it.
- **Why it qualifies**: "Changing a business rule means editing digits rather than a declaration" — "// within 30 days" is the only place the threshold has a name; `->addDays(30)` says nothing.
- **Obstruction**: Lexical Abusers
- **Suggested refactorings**: Replace with Symbolic Constant, Replace with Parameter
- **Card**: references/smells/magic-number.md

## 69. Type Embedded in Name — `app/Services/Scheduling/SchedulePrintService.php:57-335`

- **Severity/leverage**: Low — short-lived locals and one parameter; renames are mechanical, and `$orientStr` additionally hides an unextracted Orientation enum.
- **Why it qualifies**: "A name whose suffix or prefix restates the declared type" — `$dateStr`, `$orientStr`, `$dateString`, `string $addressString` all suffix the representation the declaration already carries; the card names dateString as its canonical example.
- **Obstruction**: Couplers
- **Suggested refactorings**: Extract Class, Rename Method, Rename Variable
- **Card**: references/smells/type-embedded-in-name.md

## 70. Boolean Blindness — `app/Services/Billing/AuthorizationCadenceService.php:495-496`

- **Severity/leverage**: Low — callee is Carbon, so the honest fix is the named argument `absolute: false`, restoring call-site meaning at zero cost.
- **Why it qualifies**: "Call sites that read f($x, true) where the literal's meaning is unrecoverable without opening the callee" — `diffInDays($today, false)` twice; nothing at the call site says false means "signed, not absolute", which the surrounding `max(0, ...)` depends on.
- **Obstruction**: Lexical Abusers
- **Suggested refactorings**: Introduce New Type
- **Card**: references/smells/boolean-blindness.md

## 71. Binary Operator in Name — `app/Services/Insurance/InsuranceCardParserService.php:211`

- **Severity/leverage**: Low — halves are already extracted and the name is honest; residual smell is the two-responsibility bundle behind one Filament callback.
- **Why it qualifies**: "An 'and' says the body has two halves that could each stand alone and be called separately" — parse() and fillFormFieldsFromParsedData() are separate methods this one merely chains.
- **Obstruction**: Couplers
- **Suggested refactorings**: Extract Method
- **Card**: references/smells/binary-operator-in-name.md

## 72. Flag Argument — `app/Services/Scheduling/CalendarExportService.php:401-503`

- **Severity/leverage**: Low — the production caller passes a stored guardian preference, not a bare literal, so the boolean-blindness half barely bites; leverage is untangling the two render modes.
- **Why it qualifies**: "The method is really two methods stapled together behind one name" — buildGuardianSummary/Description each early-return a wholly different output when the flag is true, and `$privacyMode` is threaded untouched through two intermediaries.
- **Obstruction**: Change Preventers
- **Suggested refactorings**: Remove Flag Argument, Extract Method
- **Card**: references/smells/flag-argument.md

## 73. Complicated Boolean Expression — `app/Services/LeadConversationSyncService.php:591`

- **Severity/leverage**: Low — homogeneous conjunction reads linearly; the real cost is keeping it in sync with the body's four checks.
- **Why it qualifies**: "Give the expression a name, because a well-named predicate is understood at a glance and a boolean expression never is" — a four-term conjunction mixing two absence sentinels that silently duplicates the four dirty-checks below it, with no name like hasNothingToBackfill.
- **Obstruction**: Obfuscators
- **Suggested refactorings**: Extract Method, Extract Variable, Use Guard Clauses, Simplify Conditional
- **Card**: references/smells/complicated-boolean-expression.md

## 74. Message Chain — `app/Services/SessionExportService.php:209,489`

- **Severity/leverage**: Low — one goalName() accessor on SessionGoalTarget removes both copies and the duplicated fallback.
- **Why it qualifies**: "The same chain is copy-pasted at several call sites, so the graph knowledge is now duplicated as well as misplaced" — `$sessionGoalTarget->sessionGoal->goal->name ?? 'Unknown Goal'` appears verbatim at both sites, fallback literal included.
- **Obstruction**: Data Dealers
- **Suggested refactorings**: Hide Delegate, Extract Method, Move Method
- **Card**: references/smells/message-chain.md

## 75. Message Chain — `app/Services/Reporting/CorrelationAnalysisService.php:390`

- **Severity/leverage**: Low — the care-team member could answer staffStartDate()/tenureMonths() directly.
- **Why it qualifies**: "Null or optional guards stack up along the walk, defending against a structure the caller should not have to know about" — the three-hop walk is preceded by two guard expressions that exist only to make it safe.
- **Obstruction**: Data Dealers
- **Suggested refactorings**: Hide Delegate, Extract Method, Move Method
- **Card**: references/smells/message-chain.md

## 76. Message Chain — `app/Services/Reporting/ClientBenchmarkService.php:101`

- **Severity/leverage**: Low — an age accessor on ClientProfile answers it once; the identical walk is already duplicated in CohortComparisonService.
- **Why it qualifies**: "Asking objects for their internals and doing the work outside them, instead of telling the object that already holds the data to answer the question" — `$clientProfile->person->dob->age` computes the client's age in the caller.
- **Obstruction**: Data Dealers
- **Suggested refactorings**: Hide Delegate, Extract Method, Move Method
- **Card**: references/smells/message-chain.md

## 77. Message Chain — `app/Services/Staff/CaseloadOverviewService.php:68-71`

- **Severity/leverage**: Low — AuthorizationLine::weeklyHours() hides the enum hop at both sites.
- **Why it qualifies**: "Telling the object that already holds the data to answer the question" — the caller reaches through `$line->serviceCode->unit_type` to invoke unitsToHours(), twice; the authorization line already holds everything needed.
- **Obstruction**: Data Dealers
- **Suggested refactorings**: Hide Delegate, Extract Method, Move Method
- **Card**: references/smells/message-chain.md

## 78. Message Chain — `app/Services/Ai/StreamAbaDataContextService.php:718`

- **Severity/leverage**: Low — ClientProfile::hasActiveTargets() answers the question where the data lives; also lazy-loads a query per goal if not eager-loaded.
- **Why it qualifies**: "A caller that needs something from a distant object walks there hop by hop" — `$clientProfile->goals->flatMap->activeTargets->isEmpty()` traverses one relation into a second; the higher-order flatMap-> is graph traversal, not an idiomatic fluent chain.
- **Obstruction**: Data Dealers
- **Suggested refactorings**: Hide Delegate, Extract Method, Move Method
- **Card**: references/smells/message-chain.md

## 79. Vertical Separation — `app/Services/Scheduling/TravelTimeService.php:288-365`

- **Severity/leverage**: Low — mechanically real but a symptom of finding 12; extracting the warning-builder method removes the gap for free.
- **Why it qualifies**: "A variable declared many lines before its first use… by the time the variable finally matters, they've forgotten what it was for" — `$isEnforced` is assigned at 288, followed by unrelated queries and the entire drive-time computation, with first use at 365.
- **Obstruction**: Obfuscators
- **Suggested refactorings**: Remove the Code Smells
- **Card**: references/smells/vertical-separation.md

## 80. Imperative Loops — `app/Services/Scheduling/DailyRouteService.php:300-322`

- **Severity/leverage**: Low — private helper, mechanical sliding(2) rewrite; modest readability win.
- **Why it qualifies**: "An explicit integer counter used only to subscript the collection… bounds arithmetic in the condition" — `$i` exists solely for `$stops[$i - 1]`/`$stops[$i]` adjacent-pair subscripting with a `$total` accumulator.
- **Obstruction**: Functional Abusers
- **Suggested refactorings**: Replace Loop with Pipeline, Replace with Built-In
- **Card**: references/smells/imperative-loops.md

## 81. Imperative Loops — `app/Services/Billing/NcciEditCheckerService.php:40-51`

- **Severity/leverage**: Low leverage — pairwise-combination is the loop's least-bad case; fix opportunistically.
- **Why it qualifies**: "Nested index loops over two collections where a join, lookup map, or flat-map would be flat" — `$i`/`$j = $i + 1` exist only to subscript; a flatMap over `$items->slice($i + 1)` names the pairwise check.
- **Obstruction**: Functional Abusers
- **Suggested refactorings**: Replace Loop with Pipeline, Replace with Built-In
- **Card**: references/smells/imperative-loops.md

## 82. Imperative Loops — `app/Services/Scheduling/UnitCalculationService.php:121-125`

- **Severity/leverage**: Trivial — one-line built-in replacement, negligible risk, low leverage beyond readability.
- **Why it qualifies**: "A counter you have to initialise, compare, and increment correctly, an accumulator declared before the loop and mutated inside it" — the counted for exists only to repeat one value; `array_fill(0, $clientCount, $totalUnits)` is the built-in.
- **Obstruction**: Functional Abusers
- **Suggested refactorings**: Replace Loop with Pipeline, Replace with Built-In
- **Card**: references/smells/imperative-loops.md

---

## Dropped in verify (28)

Candidates that tripped a surface signal but failed the card definition on
re-examination. Kept per the skill's report-header requirement; reasons
condensed.

| # | Smell | Location | Drop reason |
|---|-------|----------|-------------|
| 1 | long-parameter-list | LeadSyncService.php:65 | Card routes DI constructors to Large Class; only caller is the container |
| 2 | vertical-separation | Edi835ParserService.php:35-202 | Loop-carried accumulators; PHP scoping forbids moving them closer |
| 3 | uncommunicative-name | TravelTimeService.php:48-51 | `$a`/`$c` are the Haversine formula's published notation |
| 4 | global-data | AbstractWorkflowRuleEngine.php:38-41 | Private static, writers mechanically enumerable; belongs to inappropriate-static (which survived) |
| 5 | global-data | GlobalConfigService.php:33-51 | DB-persisted settings store behind DI; dependency visible at call sites |
| 6 | mutable-data | CareLocationMatchingService.php:160-166 | Function-local memo never escapes; single write site |
| 7 | mutable-data | HipaaAnonymizer.php:10 | Deterministically re-seeded private static; no multi-writer state |
| 8 | temporary-field | AppointmentExportService.php:14-30 | Fields initialized at construction and meaningful for the object's whole life |
| 9 | indecent-exposure | ClaimCreationResult.php:14-15 | False premise: class is `readonly`; two-field DTO's members are its API |
| 10 | combinatorial-explosion | TargetProgressService.php:91-280 | Single axis — methods are the sum of options, not the product |
| 11 | fate-over-action | TargetProgressService.php:30-51 | GoalTarget is behavior-rich; not a data class governed from outside |
| 12 | afraid-to-fail | StediDiscoveryService.php:48-76 | testConnection()'s success/message pair IS the promised result; real API throws |
| 13 | conditional-complexity | OperationalMapService.php:529-650 | Pure value-translation tables — the card's recommended solution, not the smell |
| 14 | middle-man | CaseloadPlannerService.php:25-247 | ~700-line genuine orchestrator; forwards are a minority split across two collaborators |
| 15 | clever-code | CorrelationAnalysisService.php:454-520 | PHP ships no t-distribution functions; no installed library duplicated |
| 16 | clever-code | PdfFormFieldExtractor.php:480-506 | No installed dependency covers PDF object-stream parsing with geometry |
| 17 | inappropriate-static | SqlDialectService.php:16-310 | Card carve-out: pure functions with no plausible second implementation |
| 18 | inappropriate-static | HipaaAnonymizer.php:10-95 | Deterministic memo, no behavioral leak; enclosing service injectable |
| 19 | inappropriate-static | EmailHtmlSanitizer.php:33-130 | Immutable stateless memo from hardcoded config; carve-out applies |
| 20 | inappropriate-static | ConditionalBlockProcessor.php:20-114 | Deterministic, stateless, IO-free transform; nothing to vary |
| 21 | incomplete-library-class | EmailHtmlSanitizer.php:20-80 | Gap filled once, in one owned wrapper, via public API — the card's prescribed cure |
| 22 | incomplete-library-class | InsuranceCardParserService.php:107-145 | Single disciplined fill through public API; no duplicated workarounds |
| 23 | incomplete-library-class | InsuranceCardFileUploadValue.php:11-45 | Normalized in one dedicated helper; no drifting inline copies |
| 24 | refused-bequest | SystemMergeTagGroup.php:37-45 | Contract fully honoured; ignoring unneeded context params is normal strategy slack |
| 25 | alternative-classes | AbstractWorkflowRuleEngine.php:1-517 | Engines operate on disjoint entities; no call site branches on which it holds |
| 26 | alternative-classes | SmsManagerService.php:41-124 | Three distinct contracts for disjoint channels; extra methods are genuine per-channel features |
| 27 | alternative-classes | SessionExportService.php:36-156 | Bodies do different work (session data vs note documents); renames would not converge them |
| 28 | oddball-solution | LeadSyncService.php:37-377 | One design, not two: root services compose the Lead/ family via constructor DI |
