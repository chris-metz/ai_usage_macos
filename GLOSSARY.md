# AI Usage

A macOS menu bar app that shows at a glance how much of the usage limits of your own AI subscriptions is already used, and whether you are on pace.

## Providers and limits

**Provider**:
An AI service whose limits the app shows; each provider is a tab. Claude is the first; others (e.g. Codex) follow later.
_Avoid_: vendor, service, account

**Limit**:
A usage cap of a provider, made up of a window, a utilization and a reset time.
_Avoid_: quota, budget, allowance

**Window**:
The span of time over which a limit is measured (e.g. 5 hours or 7 days) before it resets.
_Avoid_: cycle, period, interval

**Utilization**:
The percentage of a limit used in the current window.
_Avoid_: usage, consumption

**Reset time**:
The moment the current window ends and the utilization drops back to zero.
_Avoid_: expiry, renewal, reset date

**Exhausted**:
A limit at 100 % utilization: it allows no further use until its reset time.
_Avoid_: used up, full, maxed out

### Claude's limits

**Session limit**:
Claude's limit with a 5-hour window ("Current session" in Claude). Its window starts with the first message, so between windows there is none.
_Avoid_: hourly limit, 5h limit

**Weekly limit**:
Claude's limit with a 7-day window across all models.
_Avoid_: weekly quota

**Model limit**:
A weekly limit of Claude that counts only the use of one particular model. Claude decides which models have one; there can be none, one or several.
_Avoid_: model-specific limit, scoped limit

**Fable limit**:
The model limit for Fable, currently the only one.
_Avoid_: Fable usage, Fable quota

## Pace

**Pace**:
The utilization you would have now if you used a limit evenly across its whole window, i.e. the share of the window already elapsed. It rises linearly, day and night.
_Avoid_: target, expected usage

**Pace marker**:
The tick on a limit's bar that shows the pace.
_Avoid_: target line, marker

**Over pace**:
The utilization is above the pace, by at least 1 % when rounded: at the same rate the limit will be exhausted before its reset time.
_Avoid_: ahead, too fast

**Under pace**:
The utilization is below the pace, by at least 1 % when rounded: there is headroom left until the reset time.
_Avoid_: behind, buffer, reserve

**On pace**:
The utilization equals the pace when rounded to whole percent.
_Avoid_: on track, in sync
