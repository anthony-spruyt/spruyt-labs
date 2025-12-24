# Project TODOs

- ~~alerts when CPU is throttled due to heat~~ (done - node-thermal-throttling.yaml)

- Vaultwarden admin credentials uplift. Check pod logs.

- Improve workload healthchecks and probes

- Workload quality of service and priority

- check CPU throttled namespaces / workloads

- how can we generate and host our own private yaml schemas

- fix scheduler_pod_scheduling alerts

InfoInhibitor
ok
Info-level alert inhibition.
View

More
See graph
View runbook
Pending period
0s
Last evaluation
a few seconds ago
Evaluation time
0s
Labels
severity
none
Expression
(﻿ALERTS﻿{﻿severity﻿=﻿"info"﻿}﻿ == ﻿1﻿)﻿ unless ﻿on﻿(﻿namespace﻿,﻿cluster﻿)﻿ ﻿(﻿ALERTS﻿{﻿alertname﻿!=﻿"InfoInhibitor"﻿,﻿severity﻿=~﻿"warning|critical"﻿,﻿alertstate﻿=﻿"firing"﻿}﻿ == ﻿1﻿)
Description
This is an alert that is used to inhibit info alerts.
By themselves, the info-level alerts are sometimes very noisy, but they are relevant when combined with
other alerts.
This alert fires whenever there's a severity="info" alert, and stops firing when another alert with a
severity of 'warning' or 'critical' starts firing on the same namespace.
This alert should be routed to a null receiver and configured to inhibit alerts with severity="info".

Runbook URL
<https://runbooks.prometheus-operator.dev/runbooks/general/infoinhibitor>
Summary
Info-level alert inhibition.
Data source
VictoriaMetrics datasource logo VictoriaMetrics
Instances
3 firing
State
Labels
Created

Firing
recording
cluster_quantile:scheduler_pod_scheduling_sli_duration_seconds:histogram_quantile

+17 common labels
2025-12-24 14:29:40

Firing
recording
cluster_quantile:scheduler_scheduling_algorithm_duration_seconds:histogram_quantile

+17 common labels
2025-12-24 14:29:40

Firing
recording
cluster_quantile:scheduler_scheduling_attempt_duration_seconds:histogram_quantile

+17 common labels
2025-12-24 14:29:40
