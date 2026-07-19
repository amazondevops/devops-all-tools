This is a major change to the existing v2. Here we are going for subset level trafic splitting to support various istio advanced features like circuitbreaking.
https://argoproj.github.io/argo-rollouts/features/traffic-management/istio/#subset-level-traffic-splitting
Change SET:
Old config components:
Rollout
Service (canary)
Service (stable)
VirtualService

New service Components:
Rollout
Service
VirtualService
DestinationRule

