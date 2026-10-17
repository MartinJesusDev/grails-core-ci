#!/usr/bin/env bash
#
# Resuelve el perfil solicitado a un comando de Gradle y lo ejecuta dentro de
# ./grails-core. Lo invoca .github/workflows/gate.yml; no se ejecuta a mano.
#
# Entradas por entorno: PROFILE, MODULES, EXTRA, SUBDIR, LANE (matriz), REF.
set -euo pipefail

PROFILE="${PROFILE:?falta PROFILE}"
MODULES="${MODULES:-}"
EXTRA="${EXTRA:-}"
SUBDIR="${SUBDIR:-grails-forge}"
LANE="${LANE:-}"

fail() { echo "::error::$*" >&2; exit 1; }

# --- Validación de inputs -------------------------------------------------
# `extra` termina dentro de una línea de comandos, así que se rechazan los
# metacaracteres de shell (una errata no debe poder romper la invocación).
for token in ';' '|' '&' '$' '`' '<' '>' '\'; do
    if [[ "${EXTRA}" == *"$token"* ]]; then
        fail "extra contiene '$token', no permitido"
    fi
done
if [[ -n "${MODULES}" ]] && [[ ! "${MODULES}" =~ ^:[A-Za-z0-9_.-]+( :[A-Za-z0-9_.-]+)*$ ]]; then
    fail "modules inválido: '${MODULES}' (formato: ':proyecto :proyecto')"
fi

cd "${GITHUB_WORKSPACE}/grails-core"

# --- Perfiles ------------------------------------------------------------
case "${PROFILE}" in
    module)
        [[ -n "${MODULES}" ]] || fail "el perfil module requiere el input modules"
        TASKS=""
        for m in ${MODULES}; do TASKS="${TASKS} ${m}:test"; done
        ARGS="${TASKS} --continue"
        ;;
    core)
        ARGS="build -PonlyCoreTests -PskipCodeStyle --continue"
        ;;
    suite)
        [[ -n "${EXTRA}" ]] || fail "el perfil suite requiere extra con el selector, p.ej. '-PonlyMongodbTests -PskipCodeStyle'"
        ARGS="check --continue"
        ;;
    validate)
        ARGS="validateDependencyVersions validateProductionClasspath validateBomProperties validateActions --continue"
        ;;
    buildhealth)
        ARGS="buildHealth --continue"
        ;;
    docs)
        ARGS=":grails-doc:publishGuide -x aggregateGroovydoc"
        ;;
    subbuild)
        case "${SUBDIR}" in
            build-logic)
                cd build-logic
                ARGS="check --continue"
                ;;
            grails-gradle)
                cd grails-gradle
                ARGS="build --continue"
                ;;
            grails-forge)
                cd grails-forge
                ARGS="build --continue"
                ;;
            end-to-end)
                # El flujo documentado en end-to-end/README.md: publicar el
                # fixture en el repo Maven de pruebas antes de correr el check.
                ( cd grails-gradle && ./gradlew publishAllPublicationsToTestCaseMavenRepoRepository -PskipTests --continue )
                ./gradlew publishAllPublicationsToTestCaseMavenRepoRepository -PskipTests --continue
                cd end-to-end
                ARGS="check --continue"
                ;;
            *) fail "subbuild: dir desconocido '${SUBDIR}'" ;;
        esac
        ;;
    analyze|gate)
        case "${LANE}" in
            style)
                ARGS="aggregateStyleViolations validateRepositoryConventions --continue" ;;
            analysis)
                ARGS="aggregateAnalysisViolations --continue" ;;
            rat)
                ARGS="rat --continue" ;;
            validate)
                ARGS="validateDependencyVersions validateProductionClasspath validateBomProperties validateActions --continue" ;;
            core)
                ARGS="build -PonlyCoreTests -PskipCodeStyle --continue" ;;
            *) fail "perfil ${PROFILE}: falta el lane de la matriz" ;;
        esac
        if [[ "${PROFILE}" == "gate" && "${LANE}" != "validate" && "${LANE}" != "rat" ]]; then
            # El PR template pide --rerun-tasks explícitamente para el cierre.
            ARGS="${ARGS} --rerun-tasks"
        fi
        ;;
    *)
        fail "perfil desconocido: '${PROFILE}'"
        ;;
esac

# `extra` va al final a propósito: puede añadir tareas y flags que ganan a los
# del perfil (p.ej. --tests, --rerun-tasks, -PmaxTestParallel=1).
CMD="./gradlew ${ARGS} ${EXTRA} --stacktrace"

echo "::notice::ref=${REF:-?} perfil=${PROFILE}${LANE:+ lane=${LANE}} subdir=${SUBDIR}"
echo "::group::comando"
echo "${CMD}"
echo "::endgroup::"

# shellcheck disable=SC2086
exec ${CMD}
