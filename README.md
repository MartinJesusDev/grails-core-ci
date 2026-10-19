# grails-core-ci

Gate remoto y acotado para las tareas de [`MartinJesusDev/grails-core`](https://github.com/MartinJesusDev/grails-core)
(fork de [apache/grails-core](https://github.com/apache/grails-core)). Corre **solo lo que el cambio
necesita** en runners públicos gratuitos, en vez de la matriz completa de ~60 jobs del repo.

- **Repo público** → runners estándar gratuitos e ilimitados. No lo pongas privado.
- **Sin secretos**: el checkout del fork es de un repo público y la caché remota Develocity de ASF
  se lee de forma anónima.
- **Un job por gate** (3-7 en los perfiles con lanes), así que caben varios en paralelo dentro del
  límite de 20 jobs concurrentes de la cuenta.

Se lanza desde OpenCode con `/grails-core-ci-close`, o a mano:

```bash
gh workflow run gate.yml --repo MartinJesusDev/grails-core-ci \
  -f ref=fix/mi-rama -f profile=module -f modules=":grails-views-gson"
```

## Primeros pasos (clonar y configurar)

Requisitos: `gh` autenticado (`gh auth status`), `jq`, `timeout` y `column`
(coreutils/util-linux). Todo lo demás vive en este repo.

```bash
git clone git@github.com:MartinJesusDev/grails-core-ci.git
cd grails-core-ci
./install.sh          # enlaces en ~/.local/bin (git pull actualiza las herramientas)
./install.sh --copy   # alternativa: copia los scripts
gh-ci-status          # comprueba la conexión y el estado de los últimos runs
```

`install.sh` instala `gh-ci-status` y `gh-ci-watch`, y crea
`~/.local/state/gh-ci-watch/` para los logs persistentes. La convención para
OpenCode (seguimiento sin depender de un proceso vivo) está en
[`docs/opencode.md`](docs/opencode.md).

## Perfiles: qué hace cada uno y cuándo usarlo

| `profile` | Qué ejecuta exactamente | Cuándo usarlo | Tiempo |
|---|---|---|---|
| `module` | `:m:test` de cada proyecto en `modules`, con `--continue` | Iteración y regla 13 (tests del módulo tocado). Añade `:m:integrationTest`/`:m:testCli` en `extra` si el cambio toca esos source sets | 6-12 min |
| `core` | `build -PonlyCoreTests -PskipCodeStyle --continue` | La suite core (sin suites especiales), como el job principal de CI | ~60 min |
| `suite` | `check --continue` + los flags que pongas en `extra` | Acotar a mano una suite (`-PonlyMongodbTests -PskipCodeStyle`) o correr `check` con flags | variable |
| `all-suites` | 7 lanes en paralelo: `functional`, `hibernate5`, `hibernate7`, `mongodb`, `redis`, `neo4j`, `springsecurity` | **La matriz completa de tests** (GORM, seguridad, cache): equivalentes a los jobs de CI, una config cada uno | 50 min |
| `analyze` | 3 lanes: `style` (`aggregateStyleViolations validateRepositoryConventions`), `analysis` (`aggregateAnalysisViolations`), `rat` | Estilo, PMD/SpotBugs y licencias sin lanzar 3 workflows del fork | 20 min (lane más lenta) |
| `validate` | `validateDependencyVersions validateProductionClasspath validateBomProperties validateActions --continue` | Al tocar dependencias, el BOM o los workflows | 6 min |
| `buildhealth` | `buildHealth --continue --max-workers=4` con el daemon a 5G (como CI) | Cambios que afectan al grafo de dependencias entre módulos | 48 min |
| `docs` | `:grails-doc:publishGuide -x aggregateGroovydoc` | Cambios en documentación o en la guía | 7 min |
| `subbuild` | `cd <dir> && ./gradlew <tareas>` | Cambios en los builds anidados: `build-logic` (`check`), `grails-gradle` (`build`), `grails-forge` (`build`), `end-to-end` (flujo completo con fixture G7) | 8-31 min |
| `fix` | `:m:codenarcFix` de los proyectos en `modules` | Arreglar violaciones de CodeNarc de lo que tocaste sin ejecutarlo en local. **Exige `modules`** y publica el parche | ~5-10 min |
| `task` | `./gradlew <tasks>` tal cual | Cualquier tarea no cubierta: `dependencyInsight`, `compileGroovy`, `:grails-shell-cli:installDist`, `spotlessApply` de un subbuild… | variable |
| `gate` | 5 lanes: `style`, `analysis`, `rat`, `validate`, `core` — con `--rerun-tasks` en los pesados | **El cierre antes del PR** (lo que pide la plantilla de PR) | 60 min |

### Notas por perfil

- **`module`**: `extra` va al final del comando, así que puede añadir tareas y flags que ganan a los
  del perfil: `extra=":grails-core:integrationTest --tests \"pkg.Spec*\""`. Los espacios en
  `--tests` no sobreviven (se pierde el entrecomillado): usa patrones sin espacios.
- **`suite`** exige flags en `extra`; si no, falla con un mensaje que lo dice (evita correr `check`
  entero por accidente).
- **`all-suites`** corre **una configuración por suite** (JDK 21 y versiones de contenedor por
  defecto). La matriz de CI añade variantes (`jdk=25`, `indy`, versiones de contenedor) que se
  obtienen con el input `jdk` y, si hicieran falta, añadiendo las flags al perfil.
- **`subbuild`**: si pasas `tasks`, se ejecutan esas tareas en el build anidado **en lugar** de las
  por defecto. Ejemplos:
  - `-f dir=grails-forge -f tasks=spotlessApply` → formatea grails-forge (Spotless **solo** existe
    ahí; en la raíz no hay tarea `spotlessApply`).
  - `-f dir=grails-gradle -f tasks=aggregateStyleViolations`.
  - `dir=end-to-end` con `tasks` **omite** el flujo de setup (publicaciones + fixture G7); úsalo solo
    con `tasks=check` sabiendo que el setup no se ha hecho.
- **`fix`**: el `codenarcFix` del repo reescribe **todos** los `.groovy` del proyecto con regex (incluidos
  los test sources, que el chequeo de CodeNarc tiene deshabilitados), así que a nivel raíz genera un
  parche de más de 1 MB con cambios que CI **no** exige. Por eso el perfil **exige `modules`** y corre
  `:m:codenarcFix`; si de verdad quieres el repo entero, a sabiendas: `task tasks=codenarcFix`.
  **Úsalo solo cuando `analyze` tenga violaciones**: si el estilo está verde, el parche llevará cambios
  que el PR no pide (churn) y no conviene aplicarlo — medido: 26 KB en `:grails-views-gson` sobre una
  rama con el estilo en verde.
  Alternativa que arregla y verifica en el mismo ámbito que el chequeo:
  `analyze extra="-Pgrails.code-style.codenarc.fix=true"` (hace que `codenarcMain` dependa del fixer).

## Inputs

| Input | Descripción |
|---|---|
| `ref` | **Obligatorio**. Rama, tag o SHA de `MartinJesusDev/grails-core` |
| `profile` | Uno de los 12 de la tabla |
| `modules` | Proyectos Gradle separados por espacios (`':a :b'`). Solo `module` y `validate` |
| `extra` | Tareas/argumentos extra que se añaden **al final** del comando. Admite `--tests "pkg.Spec*"`, `-PmaxTestParallel=1`, `--rerun-tasks`, `-Pgrails.code-style.enabled.tests=true`… |
| `tasks` | `task`: la línea de comandos completa. `subbuild`: sobreescribe las tareas por defecto |
| `jdk` | `21` (por defecto) o `25` (island Micronaut) |
| `dir` | `subbuild`: `build-logic`, `grails-gradle`, `grails-forge` o `end-to-end` |

**Validación**: `extra` y `tasks` se rechazan si contienen `;` `|` `&` `$` `` ` `` `<` `>` `\`
(llegan a una línea de comandos). `modules` debe tener el formato `:proyecto :proyecto`.

## Fixers y parches (`changes.patch`)

Cualquier perfil puede modificar el árbol (los fixers, o un `task` que genere ficheros). Como el
runner es efímero, al terminar el script:

1. Cuenta las rutas modificadas (`git status --porcelain`).
2. Si hay cambios, escribe **`changes.patch`** (diff unificado, incluye ficheros nuevos) y lo publica
   como artefacto (`changes-<run_id>-<perfil>`, 14 días).
3. Deja constancia en el log con un `::warning::` y la lista de rutas (aunque no descargues el
   artefacto, no se pierde la información).

Aplicarlo en local:

```bash
gh run download <run-id> --repo MartinJesusDev/grails-core-ci -n changes-<run-id>-fix
git apply --3way changes.patch      # o: patch -p1 < changes.patch
```

El job queda **verde** aunque el fixer haya cambiado cosas: es una tarea de arreglo, no de
verificación. Para verificar hay que volver a lanzar `analyze` (o `gate`) sobre el árbol ya corregido.

## Cobertura: qué comando documentado cubre cada perfil

Fuentes: plantilla de PR, `CONTRIBUTING.md`, `DEVELOPMENT.md`, `AGENTS.md` de grails-core y los skills
de `.agents/skills/`.

| Comando documentado | Dónde se usa | Perfil |
|---|---|---|
| `./gradlew build --rerun-tasks` | plantilla de PR | `gate` (lane `core`, ya con `--rerun-tasks`) |
| `./gradlew codeStyle` | CONTRIBUTING | `analyze` (lane `style`) o `:m:codeStyle` vía `extra` |
| `aggregateStyleViolations`, `validateRepositoryConventions` | CI `codestyle.yml` | `analyze` (lane `style`) |
| `aggregateAnalysisViolations`, `-Pgrails.code-analysis.*` | CI `codeanalysis.yml` | `analyze` (lane `analysis`) |
| `rat` | CI `rat.yml` | `analyze` (lane `rat`) |
| `aggregateViolations` | regla 12 local | `analyze` + `core` (o `gate`), sin `clean` (el runner es limpio) |
| `codenarcFix` | skill violation-fixer | **`fix`** (exige `modules`; el repo-wide se hace con `task tasks=codenarcFix`) |
| `spotlessApply` | skill violation-fixer (solo existe en `grails-forge`) | `subbuild dir=grails-forge tasks=spotlessApply` |
| `:m:test`, `--tests`, `:m:integrationTest`, `:m:testCli` | DEVELOPMENT | `module` (+ `extra`) |
| `check`, `-PskipCodeStyle`, `-Ponly…Tests` | DEVELOPMENT | `suite` / `all-suites` / `gate` |
| `-PincludeTestTags`, `-PexcludeTestTags` | DEVELOPMENT | `extra` de `suite`/`module` |
| `-Pgrails.code-style.enabled.tests`, `-Pgrails.code-analysis.enabled.tests` | skill violation-fixer | `extra` de `analyze` |
| `validateDependencyVersions`, `validateProductionClasspath`, `validateBomProperties`, `validateActions` | AGENTS / CI | `validate` |
| `buildHealth` | AGENTS / CI `build-health.yml` | `buildhealth` |
| `:grails-doc:publishGuide -x aggregateGroovydoc` | AGENTS / CONTRIBUTING | `docs` |
| `publishAllPublicationsToTestCaseMavenRepoRepository`, `end-to-end check` | `end-to-end.yml` | `subbuild dir=end-to-end` |
| `dependencyInsight`, `jar`, `compileGroovy`, `installDist`, `groovydoc`… | skills / CI | `task` (`tasks`) |
| `bootRun`, `bootWar`, fixers de IDE, `--debug-jvm` | desarrollo de apps | **local** (no aplica en remoto) |

## Cierre de una tarea (receta canónica)

Del trabajo nuevo hasta el PR. Los pasos 1-2 son locales; el resto, remoto y gratuito.

| # | Paso | Dónde | Qué demuestra | Tiempo |
|---|---|---|---|---|
| 1 | `gx :<módulos>:test` (+ `integrationTest`/`testCli` si el cambio toca esos source sets) | local | Regla 13 de grails-core: **todos** los tests del módulo afectado | 1-10 min |
| 2 | Commit(s) + `git push -u origin <rama>` | local | — | — |
| 3 | `/grails-core-ci-close module <módulos>` | remoto | Lo mismo que el paso 1 en runner limpio (caché fría): lo que la caché local oculta | 6-12 min |
| 4 | **`gate`** | remoto | El cierre: estilo + PMD/SpotBugs + RAT + BOM/dependencias + `build --rerun-tasks -PonlyCoreTests` (lo que pide la plantilla de PR) | 60 min |
| 5 | **`all-suites`** — si el cambio toca GORM, seguridad, cache o funcionales; y para un cierre literal de la plantilla de PR | remoto | Hibernate 5/7, MongoDB, Redis, Neo4j, Spring Security y funcionales | 50 min |
| 6 | Condicionales según el cambio (tabla de abajo) | remoto | buildhealth / validate / docs / subbuild | 6-48 min |
| 7 | PR a `apache/grails-core` | ASF | **El gate definitivo de merge** (matriz completa) | 2-4 h |

Los pasos 4-6 corren **en paralelo** (perfiles distintos, grupos de concurrencia separados): reloj total ≈ 60 min.

### Condicionales por lo que toca el cambio

| Si el cambio toca… | Añade |
|---|---|
| `build-logic` | `subbuild dir=build-logic` |
| `grails-gradle` | `subbuild dir=grails-gradle` |
| `grails-forge` | `subbuild dir=grails-forge` |
| `end-to-end` o el flujo de plugins | `subbuild dir=end-to-end` |
| Dependencias / BOM (`dependencies.gradle`) | `validate` + `buildhealth` |
| `grails-doc` | `docs` |
| `.github/workflows/` | `task tasks=validateActions` |
| Violaciones de estilo | `fix` (publica `changes.patch`) |

### Lo que NO hay que lanzar

- La **matriz completa del fork** (`gradle.yml` y compañía): duplica lo que ya validan `gate` + `all-suites`; solo si quieres ver el resultado antes de que corra en ASF.
- El **gate local** (regla 12): sustituido por los perfiles remotos (decisión documentada en `~/.config/opencode/AGENTS.md`).

### Qué prueba cada cosa (para no pedir peras al olmo)

- `gate` **no** corre las suites de contenedores ni los funcionales: eso es `all-suites`.
- `gate` es la forma paralela del gate de la regla 12: mismo estilo/análisis/RAT + los tests core; sin `clean` (el runner ya es limpio) y sin el agregado `:grails-test-report:check` (los resultados por job quedan en los artefactos).
- El CI de ASF es el único visto bueno del PR: nada de esto lo sustituye.

## Leer los resultados

### `gh-ci-status` (vía principal)

`gh-ci-status` imprime el estado de los últimos runs en **una sola llamada** y
sale 0 siempre; es el comando que se ejecuta al inicio de cada turno mientras
haya gates en vuelo:

```bash
gh-ci-status                  # últimos 10 runs de grails-core-ci
gh-ci-status --limit 20
gh-ci-status --repo MartinJesusDev/grails-core
```

```
ID           ESTADO       CONCLUSIÓN  PERFIL      REF              ACTUALIZADO (UTC)
39236937813  completed    success     gate        fix/mi-rama      2026-10-19 11:55
39256623258  in_progress  -           all-suites  fix/mi-rama      2026-10-19 13:01
```

### `gh-ci-watch` (complemento, con log persistente)

Espera y resume; ya no es la única forma de enterarse. Todas las llamadas a
`gh` llevan `timeout` y reintentos, y el resultado se escribe siempre en
`~/.local/state/gh-ci-watch/<label>.log`:

```bash
gh-ci-watch --run-id 39236937813 --repo MartinJesusDev/grails-core-ci
gh-ci-watch fix/mi-rama --sha <sha> --repo MartinJesusDev/grails-core --max-wait 300
```

- `--max-wait <min>` (por defecto 90): si los runs siguen en curso, imprime el
  último estado y sale 0. Códigos: `0` verde o en curso, `1` rojo, `2` error de
  uso/API.
- Para lanzarlo en background desde un agente sin que lo mate el harness:
  `timeout 1500 gh-ci-watch --run-id <id> --max-wait 20 > /tmp/opencode/ci-watch-<id>.log 2>&1 || true`.
  Si el shell desaparece, el log persistente y `gh-ci-status` siguen ahí.

### Resultado por lane (`status.json`)

Cada job del gate publica `status-<perfil>-<lane>.json` como artifact y el job
`status` agrega todos en `status.json` (array con `run_id`, `profile`, `ref`,
`lane`, `status`, `conclusion`, `url`, `started_at` (inicio de la lane),
`finished_at`) y resume la
tabla en la página del run:

```bash
gh run download <run-id> --repo MartinJesusDev/grails-core-ci -n status
jq . status.json
gh run download <run-id> --repo MartinJesusDev/grails-core-ci -n status-gate-core
```

El resumen del run incluye la tabla `Lane | Perfil | Resultado`; si no hay
`status.json` (run cancelado antes del paso de estado), el job `status` lo dice
y no falla por ello.

### Diagnóstico

- `gh run view <id> --log-failed` para el log; `gh run download <id>` para todos
  los artefactos; en fallo se suben además `reports-*` (violations y
  test-results, 7 días).
- El fallo **no** se comenta en issues automáticamente: `GITHUB_TOKEN` solo
  escribe en este repo y el issue de seguimiento vive en `apache/grails-core`.
  El agente lo comenta desde local, con confirmación, tras ver el rojo en
  `gh-ci-status`.

## Tiempos medidos

Medidos el 2026-10-17 con el fork en `fix/16660-json-views-generator` y `fix/16615-trait-field-access-8.0.x`
(`ubuntu-latest`, 4 cores, caché de Gradle fría + caché remota Develocity en lectura):

| Perfil | Reloj |
|---|---|
| `module` (1 módulo, `:grails-views-gson`) | **6 min** |
| `module` (1 módulo, `:grails-data-hibernate7-core`) | **12 min** |
| `docs` | **7 min** |
| `subbuild` (`build-logic`) | **8 min** |
| `validate` | **6 min** |
| `suite` (`-PskipTests -PskipCodeStyle`) | **26 min** |
| `subbuild` (`end-to-end`, con fixture G7 en JDK 17) | **30 min** |
| `buildhealth` | **48 min** |
| `all-suites` | **50 min** (la lane más lenta, `mongodb` 50; `neo4j` 49; `hibernate5` 42; `springsecurity` 36; `functional` 34; `hibernate7` 34; `redis` 32) |
| `gate` | **60 min** (lo fija el lane `core`; `style` 20, `analysis` 7, `rat` 2, `validate` 2) |

Para comparar: la matriz completa del repo son ~60 jobs y 2-4 h de reloj.

## Concurrencia y coste

- Los gates de la misma rama **y perfil** se serializan (`concurrency: gate-<ref>-<profile>-<dir>`);
  perfiles o ramas distintos corren en paralelo.
- En repos públicos los runners estándar son gratuitos; el límite real es de **20 jobs concurrentes
  por cuenta** (se comparte con los runs del fork). Recomendado: **máximo 6 gates scoped a la vez**.
- Los runs del repo herramienta **no** aparecen en el PR de apache/grails-core; el PR tiene su propio CI.

## Mantenimiento

- Las versiones de `actions/*` y `gradle/actions/setup-gradle` se mantienen alineadas con las del
  repo principal (ver `.github/workflows/gate.yml`).
- `.github/scripts/gate.sh` es el único sitio donde vive la lógica de perfiles.
- `bin/gh-ci-watch` y `bin/gh-ci-status` son la única copia de las herramientas locales; `install.sh`
  las enlaza en `~/.local/bin` (o las copia con `--copy`). No las dupliques fuera del repo.
- Ver `AGENTS.md` para las convenciones si vas a tocar este repo con un agente.
