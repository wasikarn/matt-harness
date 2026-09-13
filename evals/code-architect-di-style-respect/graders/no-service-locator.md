---
type: regex
target: trace
match: not_contains
pattern: 'ServiceRegistry|ServiceLocator|get_instance\(\)|@singleton'
flags: i
---
No service-locator or singleton-registry pattern is introduced — every existing service
(`OrderService`, `RefundService`) takes its dependencies as constructor parameters, wired
explicitly in `wiring.py`.
