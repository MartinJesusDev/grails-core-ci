# Convención de seguimiento para agentes (OpenCode)

El repo no puede modificar tu configuración global de OpenCode: esto es el
bloque que hay que añadir a `~/.config/opencode/AGENTS.md` (o pegar en el
`AGENTS.md` del proyecto) para que los gates se sigan **sin depender de que un
proceso largo sobreviva**.

## Bloque para AGENTS.md

```markdown
### Seguimiento de gates (grails-core-ci)

- **Al inicio de cada turno** con gates en vuelo: `~/.local/bin/gh-ci-status`
  (una llamada, ~1 s, sale 0 siempre). Es la vía principal.
- **Al disparar**: lanza el watcher en background con log persistente:
  `timeout 1500 ~/.local/bin/gh-ci-watch --run-id <id> --repo MartinJesusDev/grails-core-ci --max-wait 20 > /tmp/opencode/ci-watch-<id>.log 2>&1 || true`
  - `--max-wait 20` cierra limpio antes del `timeout 1500` (25 min).
  - Para esperar el final de un `gate` (60 min), usa `timeout 5400` y `--max-wait 85`.
- **Si el shell del watcher desaparece**: no re-dispares el gate. Lee el log
  persistente (`~/.local/state/gh-ci-watch/<label>.log`) o ejecuta `gh-ci-status`.
- **Resultado por lane**: `gh run download <id> -n status` + `jq . status.json`
  (array con `profile`, `lane`, `conclusion`, `url`…); la tabla también está en
  la página del run (`$GITHUB_STEP_SUMMARY`).
- **Códigos de `gh-ci-watch`**: `0` verde o todavía en curso (`--max-wait`),
  `1` rojo, `2` error de uso/API.
- Las escrituras en GitHub (disparar workflows, comentar, PR…) siguen pidiendo
  confirmación explícita; la lectura con `gh` es libre.
```

## Instalación en una máquina nueva

```bash
git clone git@github.com:MartinJesusDev/grails-core-ci.git
cd grails-core-ci
./install.sh        # enlaces en ~/.local/bin; usa --copy si el repo se va a mover
gh auth status
gh-ci-status
```

`install.sh` no toca OpenCode: copia el bloque de arriba en tu `AGENTS.md` y,
si usas comandos propios (`/grails-core-ci-close`, `/grails-core-ci-status`),
haz que llamen a `gh-ci-status` y al watcher con esta misma convención.

## Por qué así

- Un shell en background puede desaparecer (sesión larga, compactación del
  harness) y el resultado se pierde. `gh-ci-status` es una consulta barata que
  se repite; el watcher solo acelera el aviso y deja rastro.
- El log persistente vive fuera de `/tmp`: sobrevive a la muerte del shell.
- El workflow publica `status.json` para no tener que interpretar logs.
