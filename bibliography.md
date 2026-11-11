---
layout: default
title: "Bibliography"
permalink: /bibliography/
description: "The reference works this site's coverage and rigor draw on. Nothing here is reproduced from them."
---

# Bibliography

This reference's chapter arc and its level of rigor draw on a short list of books
and primary documentation covering data mesh and the cloud-native platform it runs
on. They're reference works, not sources. No text or code from any of them is
reproduced in these chapters or the runnable examples. When a chapter is useful to
you, these are where to go deeper.

## Books

<table class="bib">
  <colgroup><col style="width:66%"><col style="width:34%"></colgroup>
  <thead><tr><th>Title</th><th>Author(s)</th></tr></thead>
  <tbody>
    <tr><td><a href="https://www.oreilly.com/library/view/data-mesh/9781492092384/" rel="noopener"><em>Data Mesh</em></a><br><small>O'Reilly. The four principles, the data product as architectural quantum, federated governance</small></td><td>Zhamak Dehghani</td></tr>
    <tr><td><a href="https://www.oreilly.com/library/view/designing-data-intensive-applications/9781098119058/" rel="noopener"><em>Designing Data-Intensive Applications</em>, 2nd ed.</a><br><small>O'Reilly. Reasoning about distributed systems built from independently-owned parts</small></td><td>Martin Kleppmann &amp; Chris Riccomini</td></tr>
    <tr><td><a href="https://www.manning.com/books/cloud-native-patterns" rel="noopener"><em>Cloud Native Patterns</em></a><br><small>Manning. Packaging, runtime, and platform-provided concerns for services that double as data products</small></td><td>Cornelia Davis</td></tr>
    <tr><td><a href="https://www.packtpub.com/en-us/product/cloud-native-anti-patterns-9781836200581" rel="noopener"><em>Cloud Native Anti-Patterns</em></a><br><small>Packt. The failure modes the anti-patterns chapter maps</small></td><td>Gerald Bachlmayr, Aiden Ziegelaar, Alan Blockley &amp; Bojan Zivic</td></tr>
    <tr><td><a href="https://www.oreilly.com/library/view/-/9781098131678/" rel="noopener"><em>Kubernetes Patterns</em></a><br><small>O'Reilly. Container image and workload patterns behind the build, load, and deploy sequence</small></td><td>Bilgin Ibryam &amp; Roland Huß</td></tr>
    <tr><td><a href="https://www.manning.com/books/platform-engineering-on-kubernetes" rel="noopener"><em>Platform Engineering on Kubernetes</em></a><br><small>Manning. The self-serve platform principle built out as an operating model</small></td><td>Mauricio Salatino</td></tr>
    <tr><td><a href="https://www.manning.com/books/gitops-and-kubernetes" rel="noopener"><em>GitOps and Kubernetes</em></a><br><small>Manning. Declarative delivery for the platform tier</small></td><td>Billy Yuen, Alexander Matyushentsev, Todd Ekenstam &amp; Jesse Suen</td></tr>
    <tr><td><a href="https://www.oreilly.com/library/view/learning-domain-driven-design/9781098100124/" rel="noopener"><em>Learning Domain-Driven Design</em></a><br><small>O'Reilly. Bounded contexts and domain ownership behind the service boundaries</small></td><td>Vlad Khononov</td></tr>
    <tr><td><a href="https://www.informit.com/store/implementing-domain-driven-design-9780133039894" rel="noopener"><em>Implementing Domain-Driven Design</em></a><br><small>Addison-Wesley. Aggregates, events, and context mapping in code</small></td><td>Vaughn Vernon</td></tr>
  </tbody>
</table>

## Primary documentation

<table class="bib">
  <colgroup><col style="width:34%"><col style="width:66%"></colgroup>
  <thead><tr><th>Project</th><th>Used for</th></tr></thead>
  <tbody>
    <tr><td><a href="https://fastapi.tiangolo.com/" rel="noopener">FastAPI</a></td><td>The REST framework the services are built on</td></tr>
    <tr><td><a href="https://strawberry.rocks/" rel="noopener">Strawberry GraphQL</a></td><td>The GraphQL gateway's schema-first API</td></tr>
    <tr><td><a href="https://grpc.io/docs/languages/python/" rel="noopener">gRPC (Python)</a></td><td>The inventory-service synchronous contract</td></tr>
    <tr><td><a href="https://opentelemetry.io/docs/" rel="noopener">OpenTelemetry</a></td><td>The metrics, traces, and logs signal model</td></tr>
    <tr><td><a href="https://grafana.com/docs/" rel="noopener">Grafana</a></td><td>Tempo for traces, Mimir/Prometheus for metrics</td></tr>
    <tr><td><a href="https://www.apicur.io/registry/docs/" rel="noopener">Apicurio Registry</a></td><td>The schema registry for Avro contracts</td></tr>
    <tr><td><a href="https://docs.open-metadata.org/" rel="noopener">OpenMetadata</a></td><td>The catalog, discovery, and lineage</td></tr>
    <tr><td><a href="https://istio.io/latest/docs/" rel="noopener">Istio</a></td><td>The service mesh, mTLS, and progressive delivery</td></tr>
    <tr><td><a href="https://keda.sh/docs/" rel="noopener">KEDA</a></td><td>Event-driven and lag-based autoscaling</td></tr>
    <tr><td><a href="https://strimzi.io/docs/" rel="noopener">Strimzi</a></td><td>The Kafka operator for the async backbone</td></tr>
    <tr><td><a href="https://kubernetes.io/docs/" rel="noopener">Kubernetes</a></td><td>Namespaces, RBAC, CRDs, admission control</td></tr>
    <tr><td><a href="https://minikube.sigs.k8s.io/docs/" rel="noopener">minikube</a></td><td>The local cluster, docker driver, containerd runtime</td></tr>
    <tr><td><a href="https://crc.dev/" rel="noopener">OpenShift Local (CRC)</a></td><td>The OpenShift appendix</td></tr>
  </tbody>
</table>

These titles inform this site's coverage and rigor only. Nothing in these chapters
or the runnable examples copies text or code from them.
