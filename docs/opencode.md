# Convención de seguimiento para agentes (OpenCode)

El repo no puede modificar tu configuración global de OpenCode por sí solo:
`install.sh` solo instala las herramientas en `~/.local/bin`. Este es el
bloque que hay que añadir a `~/.config/opencode/AGENTS.md` (o pegar en el
`AGENTS.md` del proyecto) para que el aviso del gate llegue al terminar sin
bloquear el turno, con log persistente y consulta a demanda.

## Bloque para AGENTS.md

```markdown
### Seguimiento de gates (watcher en background)

- **Al disparar**: lanza UN watcher en background, no bloqueante, con todos los
  run-ids pendientes:
  `timeout 5400 ~/.local/bin/gh-ci-watch --run-id <id> [--run-id <id> ...] --repo MartinJesusDev/grails-core-ci --interval 60 --max-wait 75 > /tmp/opencode/ci-watch-<label>.log 2>&1`
  - En el tool shell: `background: true`. No hace falta `timeout: 0`; los
    comandos en background no tienen timeout por defecto y `timeout 5400` es la
    red.
  - OpenCode lo muestra como tarea en curso; imprime una línea por minuto y
    avisa al terminar el último run. Ese aviso es la notificación; la salida por
    minuto es el progreso, no una notificación por línea.
  - `--max-wait 75` cubre los 60 min de `gate` y los 50 de `all-suites`.
- **Antes de lanzar**: `gh-ci-status --limit 20` para ver qué sigue en vuelo y
  `pgrep -af gh-ci-watch` para matar watchers viejos del mismo run. No repitas
  ids ya `completed`.
- **Si el watcher sale con "Los runs siguen en curso"**: dilo y consulta
  `gh-ci-status`; no re-dispares el gate.
- **Si el shell desaparece** (reinicio del server, cierre de la app,
  suspensión): no re-dispares; lee
  `~/.local/state/gh-ci-watch/<label>.log` o ejecuta `gh-ci-status`.
- **Primer plano solo si el usuario pide esperar en el turno**: el mismo
  comando sin `background: true`, con `timeout: 0` en el tool shell.
- Códigos de `gh-ci-watch`: `0` verde o en curso (`--max-wait`), `1` rojo, `2`
  error de uso/API.
- Las escrituras en GitHub siguen pidiendo confirmación explícita; la lectura
  con `gh` es libre.
```

## Instalación en una máquina nueva

```bash
git clone git@github.com:MartinJesusDev/grails-core-ci.git
cd grails-core-ci
./install.sh        # enlaces en ~/.local/bin; usa --copy si el repo se va a mover
gh auth status
gh-ci-status
```

`install.sh` no toca OpenCode. Para que la convención quede completa:

1. Copia el bloque de arriba en `~/.config/opencode/AGENTS.md` (global) o en el
   `AGENTS.md` del proyecto.
2. Si usas comandos propios (`/grails-core-ci-close`, `/grails-core-ci-status`),
   actualiza sus templates en `~/.config/opencode/opencode.jsonc` para que
   llamen a `gh-ci-status` y lancen el watcher en background.
3. Reinicia OpenCode o abre una sesión nueva para que cargue la configuración.

**Si te ayuda una IA a instalar esto**, pídele explícitamente que haga también
los pasos 1-3: el repo no puede escribir en tu `$HOME` por su cuenta, pero un
agente con acceso a tus archivos sí puede (con tu confirmación). Si solo ejecuta
`install.sh`, las herramientas funcionan pero la convención de seguimiento no
se aplica.

## Por qué así

- OpenCode 2.1.0 corrigió el corte de shells a los 5 min (#55149): un watcher
  en background puede sobrevivir el `gate` de 60 min, imprimir una línea por
  minuto y avisar al terminar, sin bloquear el turno.
- `--max-wait 75` cubre `gate` (60) y `all-suites` (50); `timeout 5400` es la
  red por si el script se cuelga.
- El log persistente (`~/.local/state/gh-ci-watch/`) es la red para reinicios
  del server, cierres de la app o suspensión; `gh-ci-status` es la consulta
  barata previa y de recuperación.
- OpenCode avisa al terminar el shell; la salida por minuto es el progreso, no
  una notificación push por cada línea.
