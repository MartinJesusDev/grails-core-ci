# Agent Guide for grails-core-ci

Herramienta personal de CI acotado para [`MartinJesusDev/grails-core`](https://github.com/MartinJesusDev/grails-core)
(fork de apache/grails-core). **No es el producto**: es el andamio para validar tareas de grails-core
en la nube sin tocar la máquina local.

Si trabajas en grails-core, lee antes el bloque `gradle-memory` de `~/.config/opencode/AGENTS.md`
(reglas de la máquina: `gx`, slice, qué se prohíbe en local) — este repo es la mitad remota de eso.

## Reglas de oro

1. **Público y sin secretos.** Runners gratuitos e ilimitados; cualquier secret o fork privado rompe
   el modelo (una corrida de la matriz completa ≈ miles de minutos del cupo).
2. **Todo lo que ejecuta vive en `.github/scripts/gate.sh`.** No dupliques la lógica de perfiles en el
   workflow. El workflow solo mapea inputs → entorno y publica artefactos.
3. **Escritura en GitHub siempre con confirmación del usuario** (`gh workflow run`, `gh pr create`,
   comentarios, labels, secrets…). Este repo no es la excepción.
4. **`ref` es de `MartinJesusDev/grails-core`**, no de este repo. Los runs de aquí se identifican con
   `run-name: gate [<perfil>] <ref> <módulos>`.
5. **Nunca dejes un gate sin vigilar.** Dispara y lanza `gh-ci-watch --run-id <id>` en background.

## Arquitectura

```
.github/workflows/gate.yml     # 4 jobs: scoped, all-suites (7 lanes), analyze (3), gate (5)
.github/actions/setup/action.yml  # checkout del fork al ref + JDK liberica + setup-gradle
.github/scripts/gate.sh        # ÚNICA fuente de verdad: perfil + inputs → comando de Gradle
README.md                      # documentación de uso (perfiles, inputs, tiempos, cobertura)
```

- El job `scoped` cubre un perfil de un solo job; `all-suites`, `analyze` y `gate` usan matrices de
  lanes (una lane por suite / grupo de tareas), lo que mantiene cada job muy por debajo del límite
  de 6 h de GitHub.
- El checkout del fork va a `./grails-core` (el workspace raíz es este repo, para poder usar la
  acción compuesta local).
- Las versiones de `actions/*` y `gradle/actions/setup-gradle` se copian del repo principal.

## Perfiles

La tabla completa (qué hace cada uno, cuándo usarlo, tiempos medidos) está en el `README.md`. Resumen:

`module` · `core` · `suite` · `all-suites` · `analyze` · `validate` · `buildhealth` · `docs` ·
`subbuild` · `fix` · `task` · `gate`

## Añadir o cambiar un perfil

1. Añade el caso en el `case "${PROFILE}"` de `gate.sh` (y en el `case "${LANE}"` si es un perfil con
   lanes). Si el perfil muta el árbol, exige los inputs que acoten el daño (como `fix`, que requiere
   `modules` porque su tarea a nivel raíz reescribe todo el repo).
2. Si es un perfil con lanes, añade el job con su matriz en `gate.yml` y **exclúyelo** del `if:` del
   job `scoped` (si no, correría dos veces).
3. Si necesita un input nuevo, decláralo en `workflow_dispatch.inputs` y pásalo en el `env:` de cada
   job (todos los jobs comparten el mismo contrato de entorno).
4. Actualiza el `README.md` (tabla de perfiles + cobertura) y, si aplica, los tiempos medidos.
5. Valida antes de subir:
   ```bash
   bash -n .github/scripts/gate.sh
   python3 -c "import yaml; yaml.safe_load(open('.github/workflows/gate.yml'))"
   ```
6. Prueba el perfil con un dispatch real sobre una rama ya pusheada del fork.

## Convenciones del script

- **Validación**: `extra` y `tasks` se rechazan si contienen `;` `|` `&` `$` `` ` `` `<` `>` `\`, y
  `modules` debe casar `^(:[A-Za-z0-9_.-]+( :[A-Za-z0-9_.-]+)*)$`. Son datos que llegan a una línea de
  comandos: no las relajes sin sustituto.
- **Orden**: la tarea base del perfil primero, `extra` al final (así puede añadir tareas y flags que
  ganan). `--stacktrace` se añade siempre.
- **Parches**: tras ejecutar, el script cuenta los cambios (`git status --porcelain`), escribe
  `changes.patch` (`git add -A -N` + `git diff`, incluye ficheros nuevos) en `$GITHUB_WORKSPACE` y lo
  publica el workflow con `if: always()` como `changes-<run_id>-<perfil>`. El job sale verde aunque
  haya cambios: los fixers arreglan, no verifican.
- **Artefactos en fallo**: `reports-<run_id>-<perfil>` con `**/build/reports/violations/**`,
  `**/build/test-results/**` y el reporte agregado de `grails-test-report`.
- **Idempotencia**: no añadas pasos que muten el repo fuera de los perfiles de arreglo (`fix`,
  `task` con una tarea que escribe).

## Comandos útiles

```bash
# lanzar
gh workflow run gate.yml --repo MartinJesusDev/grails-core-ci \
  -f ref=<rama> -f profile=<perfil> [-f modules=":a :b"] [-f extra="..."] [-f tasks="..."]

# vigilar (acepta varios --run-id)
~/.local/bin/gh-ci-watch --run-id <id> --repo MartinJesusDev/grails-core-ci --interval 60

# estado
gh run list --repo MartinJesusDev/grails-core-ci --limit 20 --json databaseId,status,conclusion,displayTitle

# diagnóstico
gh run view <id> --repo MartinJesusDev/grails-core-ci --log-failed
gh run download <id> --repo MartinJesusDev/grails-core-ci
```

## Limitaciones conocidas

- Las lanes de `all-suites` corren **una configuración** por suite (JDK 21, versiones de contenedor
  por defecto); las variantes de CI (JDK 25, `indy`, versiones) no están cubiertas salvo con `jdk=25`.
- `end-to-end` necesita el fixture G7 en JDK 17 y depende de `JAVA_HOME_17_X64` del runner; si el
  runner deja de exponerlo, el perfil falla con mensaje explícito (nunca da un falso verde).
- `spotlessApply` no existe en la raíz de grails-core; solo en `grails-forge` (vía `subbuild`).
- El CI del PR en apache/grails-core es independiente y no es reducible: este repo es pre-vuelo.
