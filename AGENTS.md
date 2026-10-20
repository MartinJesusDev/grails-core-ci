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
5. **El aviso llega con el watcher en background.** Dispara y lanza UN watcher no bloqueante con
   todos los run-ids pendientes (`--max-wait 75`, `background: true`, log persistente); avisa al
   terminar. `gh-ci-status` es la consulta previa y la red si el shell desaparece (ver "Comandos
   útiles" y `docs/opencode.md`).

## Arquitectura

```
.github/workflows/gate.yml     # 4 jobs: scoped, all-suites (7 lanes), analyze (3), gate (5), + status
.github/actions/setup/action.yml   # checkout del fork al ref + JDK liberica + setup-gradle
.github/actions/status/action.yml  # resultado de cada lane → status.json + artifact + resumen
.github/scripts/gate.sh        # ÚNICA fuente de verdad: perfil + inputs → comando de Gradle
bin/gh-ci-watch                # espera acotada, con timeout/reintentos y log persistente
bin/gh-ci-status               # estado de los últimos runs en una sola llamada
install.sh                     # instala bin/ en ~/.local/bin (enlaces o copias)
docs/opencode.md               # convención de seguimiento para agentes
README.md                      # documentación de uso (perfiles, inputs, tiempos, cobertura)
```

- El job `scoped` cubre un perfil de un solo job; `all-suites`, `analyze` y `gate` usan matrices de
  lanes (una lane por suite / grupo de tareas), lo que mantiene cada job muy por debajo del límite
  de 6 h de GitHub.
- El checkout del fork va a `./grails-core` (el workspace raíz es este repo, para poder usar la
  acción compuesta local).
- Las versiones de `actions/*` y `gradle/actions/setup-gradle` se copian del repo principal.
- `install.sh` solo instala `bin/` en `~/.local/bin`; la configuración global de OpenCode
  (`~/.config/opencode/AGENTS.md` y `opencode.jsonc`) no se toca desde el repo. Un agente con acceso al
  home puede aplicarla con confirmación (ver `docs/opencode.md`).

## Perfiles

La tabla completa (qué hace cada uno, cuándo usarlo, tiempos medidos) está en el `README.md`. Resumen:

`module` · `core` · `suite` · `all-suites` · `analyze` · `validate` · `buildhealth` · `docs` ·
`subbuild` · `fix` · `task` · `gate`

## Añadir o cambiar un perfil

1. Añade el caso en el `case "${PROFILE}"` de `gate.sh` (y en el `case "${LANE}"` si es un perfil con
   lanes). Si el perfil muta el árbol, exige los inputs que acoten el daño (como `fix`, que requiere
   `modules` porque su tarea a nivel raíz reescribe todo el repo).
2. Si es un perfil con lanes, añade el job con su matriz en `gate.yml` y **exclúyelo** del `if:` del
   job `scoped` (si no, correría dos veces). Añade el paso `Gate status` (`if: always()`,
   `continue-on-error: true`) al final del job; el job `status` lo agrega sin tocar nada más.
3. Si necesita un input nuevo, decláralo en `workflow_dispatch.inputs` y pásalo en el `env:` de cada
   job (todos los jobs comparten el mismo contrato de entorno).
4. Actualiza el `README.md` (tabla de perfiles + cobertura) y, si aplica, los tiempos medidos.
5. Valida antes de subir:
   ```bash
   bash -n .github/scripts/gate.sh bin/gh-ci-watch bin/gh-ci-status install.sh
   python3 -c "import yaml; yaml.safe_load(open('.github/workflows/gate.yml'))"
   python3 -c "import yaml; yaml.safe_load(open('.github/actions/status/action.yml'))"
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
- **Estado por lane**: el paso `Gate status` publica `status-<perfil>-<lane>.json` (artifact
  `status-<perfil>-<lane>`) y el job `status` agrega todo en `status.json` (artifact `status`) y lo
  resume en `$GITHUB_STEP_SUMMARY`. Los pasos son `continue-on-error`: si la observabilidad falla, el
  gate no se vuelve rojo por ello.
- **Idempotencia**: no añadas pasos que muten el repo fuera de los perfiles de arreglo (`fix`,
  `task` con una tarea que escribe).

## Comandos útiles

```bash
# instalar las herramientas locales (una vez por clon)
./install.sh

# lanzar
gh workflow run gate.yml --repo MartinJesusDev/grails-core-ci \
  -f ref=<rama> -f profile=<perfil> [-f modules=":a :b"] [-f extra="..."] [-f tasks="..."]

# estado previo y red si el shell desaparece (una llamada, ~1 s; sale 0 siempre)
gh-ci-status --limit 20

# ver watchers viejos antes de lanzar el nuevo
pgrep -af gh-ci-watch

# vigilar en background, sin bloquear el turno (tool shell: background: true)
timeout 5400 gh-ci-watch --run-id <id> [--run-id <id> ...] \
  --repo MartinJesusDev/grails-core-ci --interval 60 --max-wait 75 \
  > /tmp/opencode/ci-watch-<label>.log 2>&1

# resultado por lane
gh run download <id> --repo MartinJesusDev/grails-core-ci -n status && jq . status.json

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
- `fix` exige `modules` y solo merece la pena cuando `analyze` tiene violaciones: su tarea reescribe
  más de lo que el chequeo mira (incluye test sources), así que con el estilo en verde el parche es
  churn que el PR no debe llevar.
- **No hay notificación automática en issues**: `GITHUB_TOKEN` solo puede escribir en este repo y el
  issue de seguimiento vive en `apache/grails-core`. El fallo se ve con `gh-ci-status` y el agente lo
  comenta desde local con su `gh` autenticado, previa confirmación.
- **Si el shell desaparece** (reinicio del server, cierre de la app, suspensión): el watcher en
  background no puede avisar. No re-dispares el gate: lee
  `~/.local/state/gh-ci-watch/<label>.log` o ejecuta `gh-ci-status`. El log persistente es la red,
  no la vía principal.
- El CI del PR en apache/grails-core es independiente y no es reducible: este repo es pre-vuelo.
