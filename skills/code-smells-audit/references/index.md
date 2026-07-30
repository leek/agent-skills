# Smell Index — by Occurrence Lens

All 56 smells of the catalog, grouped under the 9 occurrence lenses. Each
detection pass sweeps one lens, armed with the one-line descriptions below,
and loads a full card from `smells/<slug>.md` only for candidate matches.
Descriptions are quoted from the upstream catalog (see
[ATTRIBUTION.md](ATTRIBUTION.md)).

## Responsibility (11)

- **[Afraid To Fail](smells/afraid-to-fail.md)** — Every caller has to check whether things actually worked, because this code returns status codes instead of throwing exceptions. The defensive ifs cascade up the entire call chain.
- **[Combinatorial Explosion](smells/combinatorial-explosion.md)** — Dozens of methods that do almost the same thing, each differing by one small detail. Add a new feature and the count multiplies again. Good luck remembering which variant handles which edge case.
- **[Divergent Change](smells/divergent-change.md)** — A class that changes for database reasons on Monday, calculation reasons on Wednesday, and display reasons on Friday. Same file, different reasons, and the merge conflicts pile up every sprint.
- **[Dubious Abstraction](smells/dubious-abstraction.md)** — A method that orchestrates a business workflow but also opens its own database connection, mixing strategy with plumbing until you can't tell what level of abstraction you're reading.
- **[Fate over Action](smells/fate-over-action.md)** — A class that holds data but owns none of the behavior operating on it. External code reaches in, pulls values out, and makes decisions the object never learned to make for itself.
- **[Feature Envy](smells/feature-envy.md)** — A method that touches another class's fields more than its own. It was written in the wrong place and belongs closer to the data it can't stop reaching for.
- **[Insider Trading](smells/insider-trading.md)** — Two classes exchanging private implementation details they shouldn't have access to — the kind of under-the-table knowledge sharing that makes either one impossible to change without breaking the other.
- **[Parallel Inheritance Hierarchies](smells/parallel-inheritance-hierarchies.md)** — Add a BasicUser, and you need a BasicFunctions. Add a PremiumUser, and here comes PremiumFunctions. Every subclass in one hierarchy demands a mirror in the other, and the cost of every new feature doubles.
- **[Required Setup or Teardown Code](smells/required-setup-or-teardown-code.md)** — Close the socket when you're done. Check the environment variables before you start. Reset the state after every call. The object could handle all of this internally. Instead, it made it your problem.
- **[Shotgun Surgery](smells/shotgun-surgery.md)** — One small feature change. A dozen files to edit. You submit the PR, then find two more files you missed.
- **[Side Effects](smells/side-effects.md)** — set_gold(amount) sounds simple enough. Except it also triggers a dancing animation and resets the payday timer. Methods that do more than their name promises hide behavior callers never asked for and debuggers never suspect.

## Names (11)

- **["What" Comment](smells/what-comment.md)** — Comments that narrate what the code does instead of why — a deodorant sprayed over smelly code, where extracting a well-named method would eliminate both the smell and the comment.
- **[Binary Operator in Name](smells/binary-operator-in-name.md)** — If a method has "and" or "or" in its name, it's confessing to doing two things, and that confession is an invitation to split it in half.
- **[Boolean Blindness](smells/boolean-blindness.md)** — Does filter(true) mean take or drop? When a function operates on raw booleans, it destroys the information about what those values represent. The type system knows; the reader doesn't.
- **[Complicated Regex Expression](smells/complicated-regex-expression.md)** — A regex pattern so dense it needs an online decomposer to parse. Named variables and a builder function would make the same expression self-documenting.
- **[Fallacious Comment](smells/fallacious-comment.md)** — A comment that was true once but now lies. The code changed, the comment didn't, and there's no linter that catches the drift.
- **[Fallacious Method Name](smells/fallacious-method-name.md)** — getItems() returns a single item. isValid() returns a string. setValue() quietly returns a value too. Method names that betray every convention programmers have built over decades.
- **[Inconsistent Names](smells/inconsistent-names.md)** — The mental shortcuts that let developers navigate by pattern break when one class calls it store(), another says add(), and a third insists on put(). Same operation. Three names. Zero muscle memory.
- **[Inconsistent Style](smells/inconsistent-style.md)** — Mixed formatting, flipped parameter orders, and clashing conventions in the same codebase. The code works, but the inconsistency saps trust. If they couldn't agree on style, what else didn't they agree on?
- **[Magic Number](smells/magic-number.md)** — A bare 86400 in the code — is that seconds in a day, a timeout, or a config limit? Unnamed numbers hide intent, and when the same literal appears in five places, changing one means hunting for the rest.
- **[Type Embedded in Name](smells/type-embedded-in-name.md)** — playerName, dateString, userList: the type is already in the annotation, and now it's in the name too. Redundant today, misleading tomorrow when the type changes but the name doesn't.
- **[Uncommunicative Name](smells/uncommunicative-name.md)** — data, val, m1, temp, get_f(). The code compiles fine. Understanding it requires reverse-engineering every abbreviation the original author thought was self-evident.

## Data (8)

- **[Data Clump](smells/data-clump.md)** — red, green, and blue passed separately to every function that needs a color. The same variables travel together everywhere, never packaged into the object they're quietly begging to become.
- **[Global Data](smells/global-data.md)** — Any code, anywhere, can read and write these variables. When something breaks, every function in the codebase is a suspect.
- **[Hidden Dependencies](smells/hidden-dependencies.md)** — The class works perfectly in the developer's environment and crashes in production. You read the stack trace, search every constructor, and find nothing. The dependency was silently resolved from the environment.
- **[Indecent Exposure](smells/indecent-exposure.md)** — Everything's public. Nothing's hidden. Other modules couple to implementation details they were never meant to see, and now you can't change a private algorithm without breaking six callers who shouldn't have known it existed.
- **[Mutable Data](smells/mutable-data.md)** — Data that anything can modify at any time. The bug reproduces instantly in production and vanishes in your debugger — by the time you pause execution, something else already changed the value.
- **[Primitive Obsession](smells/primitive-obsession.md)** — A phone number stored as a string. A price stored as a float. Concepts that deserve their own types get crammed into primitives, losing validation, scattering logic, and pretending a bare string is something it's not.
- **[Temporary Field](smells/temporary-field.md)** — A field that's null eleven months of the year and suddenly matters during one specific calculation. The object carries it everywhere, for one brief moment of relevance.
- **[Tramp Data](smells/tramp-data.md)** — Data hitchhiking through a chain of methods that never use it. Each function accepts the parameter, ignores it, and passes it along — just so the one at the end of the line can finally read it.

## Unnecessary Complexity (7)

- **[Clever Code](smells/clever-code.md)** — Code that works but makes you feel stupid for not understanding it. Reinvented built-ins, abused language quirks, logic compacted into one-liners that nobody else can maintain.
- **[Dead Code](smells/dead-code.md)** — You read past it wondering if it's safe to delete. Unreachable branches, commented-out blocks, functions that last ran in 2019. They cost nothing at runtime but tax every developer who encounters them.
- **[Imperative Loops](smells/imperative-loops.md)** — for(i=0; i<len; i++) — the ceremony of manually tracking indexes, accumulating results, and handling off-by-one errors, when a map, filter, or built-in says the same thing in one line.
- **[Lazy Element](smells/lazy-element.md)** — The meeting that could have been an email — except it's a class. One field, one method that just delegates to another, an abstraction that costs more in complexity than it ever returns in clarity.
- **[Obscured Intent](smells/obscured-intent.md)** — You stare at the function for five minutes before realizing it calculates overtime pay. Between the single-letter variables, the magic numbers, and the missing whitespace, the intent is buried under layers of accidental obfuscation.
- **[Speculative Generality](smells/speculative-generality.md)** — An abstract base class for a hierarchy that never grew. Three extra parameters for a feature you were sure someone would request. Abstractions built for a future that never arrived, cluttering the code with unused generality.
- **[Status Variable](smells/status-variable.md)** — found = False. Then a loop. Then found = True somewhere inside. Then a check after. Mutable flags that complicate control flow when a direct return or a built-in would express the same logic in a single line.

## Conditional Logic (6)

- **[Callback Hell](smells/callback-hell.md)** — Nested callbacks indented so deep the closing brackets cascade like a staircase to nowhere. The actual logic hides somewhere around indent level five.
- **[Complicated Boolean Expression](smells/complicated-boolean-expression.md)** — Reading it feels like solving a discrete math problem. The if-statement just checks whether a timer expired, but between the negations and conjunctions, you'd never guess that at a glance.
- **[Conditional Complexity](smells/conditional-complexity.md)** — The if/else chain that grows a new branch with every feature. First it's readable. Then it's manageable. Then it's a 200-line switch statement, and suddenly the polymorphism refactor everyone avoided is the only option left.
- **[Flag Argument](smells/flag-argument.md)** — A boolean parameter that forces the caller to write book(marcel, false) — and everyone who reads it to wonder: false what?
- **[Null Check](smells/null-check.md)** — Defensive null checks scattered everywhere like a nervous tic — each one a band-aid over a missing Null Object, and each a reminder that Tony Hoare called his invention a billion-dollar mistake.
- **[Special Case](smells/special-case.md)** — The if-statement that handles "one weird edge case" before the real logic begins. It was a hotfix once. It was never properly refactored. Now every future reader has to hold that branch in their head alongside everything else.

## Interfaces (4)

- **[Base Class depends on Subclass](smells/base-class-depends-on-subclass.md)** — When a parent class reaches down to reference its own children, the inheritance tree grows upside down. Change a leaf, redeploy the trunk.
- **[Inappropriate Static](smells/inappropriate-static.md)** — Impossible to override. Painful to mock. Silently coupling everything that calls them. Static methods are convenient right up until the behavior needs to vary: then they're a dead end.
- **[Incomplete Library Class](smells/incomplete-library-class.md)** — A third-party library that does 95% of what you need. The missing 5% means building workarounds that duplicate effort, drift from the original, and never feel like first-class code.
- **[Refused Bequest](smells/refused-bequest.md)** — A Tower that extends Minion but throws NotImplemented on move(). The inheritance contract promises full support; the subclass delivers a runtime exception and an apology.

## Measured Smells (4)

- **[Large Class](smells/large-class.md)** — The God Class. Too many methods, too many fields, too many reasons to exist. Reading it takes a morning, testing it takes a sprint, and changing it is a gamble that affects everything it touches.
- **[Long Method](smells/long-method.md)** — A method so long you scroll past the beginning before reaching the end. Every change requires re-reading the whole thing, every piece of logic is trapped inside, and the side effects could be hiding three screens away.
- **[Long Parameter List](smells/long-parameter-list.md)** — Five arguments. Six. Seven. At some point the function signature becomes a riddle, the caller needs a cheat sheet, and the method is clearly trying to do more than one thing.
- **[Vertical Separation](smells/vertical-separation.md)** — Variables declared at the top of a method, used fifty lines later. By the time you reach the logic that needs them, you've already forgotten what half the variables were for.

## Duplication (3)

- **[Alternative Classes with Different Interfaces](smells/alternative-classes-with-different-interfaces.md)** — Two classes. Same job. Different spelling. One says hug_zombie(), the other says hug_snowman(), and neither realizes they're duplicating logic behind method names that could share a single interface.
- **[Duplicated Code](smells/duplicated-code.md)** — The same logic in five places. Change one, miss another, and watch the behavior quietly diverge. According to Fowler, this is the single worst smell in a codebase.
- **[Oddball Solution](smells/oddball-solution.md)** — Same problem, two solutions, different files. One uses an adapter, the other rolls its own socket logic, and you can't tell which approach is the correct one. Or if either is.

## Message Calls (2)

- **[Message Chain](smells/message-chain.md)** — object.getA().getB().getC().getD() — the caller knows the entire relationship chain, and every intermediate link becomes a dependency that breaks when any relationship changes.
- **[Middle Man](smells/middle-man.md)** — Half its methods just call the same method on another class. It exists, it delegates, and its author can't explain what it adds. Remove it, and nothing breaks.
