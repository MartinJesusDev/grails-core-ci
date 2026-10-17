# grails-core-ci

Gate remoto y acotado para las tareas de [`MartinJesusDev/grails-core`](https://github.com/MartinJesusDev/grails-core)
(fork de apache/grails-core). Corre **solo lo que el cambio necesita** en runners
públicos gratuitos, en vez de la matriz completa de ~60 jobs del repo.

Se lanza desde OpenCode con `/grails-core-ci-close`, o a mano:

```bash
gh workflow run gate.yml --repo MartinJesusDev/grails-core-ci \
  -f ref=fix/mi-rama -f profile=module -f modules=":grails-views-gson"
```

## Perfiles

| `profile` | Qué ejecuta | Uso típico |
|---|---|---|
| `module` | `:m:test` de los módulos indicados | iteración y regla 13 (tests del módulo afectado) |
| `core` | `build -PonlyCoreTests -PskipCodeStyle` | la suite core sin suites especiales |
| `suite` | `check` + los flags de `extra` (`-PonlyMongodbTests -PskipCodeStyle`…) | suites funcionales y de contenedores |
| `analyze` | 3 jobs en paralelo: `style` (`aggregateStyleViolations validateRepositoryConventions`), `analysis` (`aggregateAnalysisViolations`), `rat` | estilo, PMD/SpotBugs, licencias |
| `validate` | `validateDependencyVersions validateProductionClasspath validateBomProperties validateActions` | BOM y dependencias |
| `buildhealth` | `buildHealth` | clases duplicadas |
| `docs` | `:grails-doc:publishGuide -x aggregateGroovydoc` | guía de usuario |
| `subbuild` | build anidado (`build-logic`, `grails-gradle`, `grails-forge`, `end-to-end`) | cambios fuera del root |
| `gate` | 5 jobs en paralelo: `style`, `analysis`, `rat`, `validate`, `core` — con `--rerun-tasks` en los lanes pesados | **el cierre completo** antes del PR |

## Inputs

| Input | Descripción |
|---|---|
| `ref` | rama, tag o SHA de `MartinJesusDev/grails-core` (obligatorio) |
| `modules` | proyectos Gradle separados por espacios (`':a :b'`) |
| `extra` | tareas/argumentos extra que se añaden al final del comando. Admite `--tests "pkg.Spec*"`, `-PmaxTestParallel=1`, `--rerun-tasks`… Se rechazan `; \| & $ \` < > \` |
| `jdk` | `21` (por defecto) o `25` (island Micronaut) |
| `dir` | build anidado para `subbuild` |

## Concurrencia y coste

Cada gate scoped usa 1 job (los perfiles `analyze` y `gate`, 3 y 5). En repos
públicos los runners estándar son gratuitos. Los gates de la misma rama **y
perfil** se serializan (`concurrency: gate-<ref>-<profile>`); perfiles o ramas
distintos corren en paralelo.

Los reportes de fallo (violations y test-results) se suben como artefactos con
7 días de retención.

## Mantenimiento

- Las versiones de `actions/*` y `gradle/actions/setup-gradle` se mantienen
  alineadas con las del repo principal.
- `gate.sh` es el único sitio donde vive la lógica de perfiles.
