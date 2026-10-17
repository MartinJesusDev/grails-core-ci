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
TASKS="${TASKS:-}"

fail() { echo "::error::$*" >&2; exit 1; }

# --- Validación de inputs -------------------------------------------------
# `extra` y `tasks` terminan dentro de una línea de comandos, así que se
# rechazan los metacaracteres de shell (una errata no debe poder romper la
# invocación).
for token in ';' '|' '&' '$' '`' '<' '>' '\'; do
    if [[ "${EXTRA}" == *"$token"* ]]; then
        fail "extra contiene '$token', no permitido"
    fi
    if [[ "${TASKS}" == *"$token"* ]]; then
        fail "tasks contiene '$token', no permitido"
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
        # buildHealth explota jars y crece mucho en el daemon; el repo lo corre
        # en CI con 5G (ver .github/workflows/build-health.yml).
        export GRADLE_OPTS="-Dorg.gradle.jvmargs=-Xmx5G"
        ARGS="buildHealth --continue --max-workers=4"
        ;;
    docs)
        ARGS=":grails-doc:publishGuide -x aggregateGroovydoc"
        ;;
    subbuild)
        case "${SUBDIR}" in
            build-logic|grails-gradle|grails-forge|end-to-end) ;;
            *) fail "subbuild: dir desconocido '${SUBDIR}'" ;;
        esac
        if [[ -n "${TASKS}" ]]; then
            # Tareas explícitas dentro del build anidado, p.ej.
            # `dir=grails-forge tasks=spotlessApply`.
            cd "${SUBDIR}"
            ARGS="${TASKS}"
        elif [[ "${SUBDIR}" == "end-to-end" ]]; then
            # Flujo de end-to-end/README.md y .github/workflows/end-to-end.yml:
            # (1) publicar Grails y los plugins en el repo Maven de pruebas,
            # (2) construir el fixture precompilado Grails 7 con JDK 17 (el
            # del toolcache del runner), (3) check del build end-to-end.
            ( cd grails-gradle && ./gradlew publishAllPublicationsToTestCaseMavenRepoRepository -PskipTests --continue )
            ./gradlew publishAllPublicationsToTestCaseMavenRepoRepository -PskipTests --continue

            fixture_jdk="${JAVA_HOME_17_X64:-}"
            [[ -n "${fixture_jdk}" ]] || fail "end-to-end: el runner no expone JAVA_HOME_17_X64 (JDK 17) para el fixture G7"
            ( cd end-to-end/legacy-g7-command-plugin && JAVA_HOME="${fixture_jdk}" ./gradlew jar --stacktrace ) ||
                fail "end-to-end: falló la construcción del fixture G7"

            # El fixture debe ser bytecode Java 17 (major 61): si se construyera
            # con otro JDK, el check pasaría sin probar nada.
            fixture_jar=$(ls end-to-end/legacy-g7-command-plugin/build/libs/*.jar 2>/dev/null | head -1 || true)
            fixture_major=$(unzip -p "${fixture_jar:-/nonexistent}" legacy/g7/commands/HelloG7PrecompiledCommand.class 2>/dev/null |
                od -An -t u1 -j 6 -N 2 | awk 'NF { print $1 * 256 + $2; exit }' || true)
            [[ "${fixture_major}" == "61" ]] ||
                fail "end-to-end: el fixture no es bytecode Java 17 (major=${fixture_major:-?}, jar=${fixture_jar:-?})"

            export DO_NOT_CACHE_TESTS=1
            cd end-to-end
            ARGS="check --continue"
        else
            cd "${SUBDIR}"
            case "${SUBDIR}" in
                build-logic)   ARGS="check --continue" ;;
                grails-gradle) ARGS="build --continue" ;;
                grails-forge)  ARGS="build --continue" ;;
            esac
        fi
        ;;
    all-suites)
        # Las suites especializadas, una por lane en paralelo (en un solo job
        # el conjunto se pasa del límite de 6 h de GitHub). Los flags replican
        # los jobs equivalentes de .github/workflows/gradle.yml.
        case "${LANE}" in
            functional)     FLAGS="-PonlyFunctionalTests -PskipCodeStyle -PskipHibernate5Tests -PskipHibernate7Tests -PskipMongodbTests -PskipNeo4jTests -PskipSpringSecurityTests -PskipRedisTests" ;;
            hibernate5)     FLAGS="-PonlyHibernate5Tests -PskipCodeStyle" ;;
            hibernate7)     FLAGS="-PonlyHibernate7Tests -PskipCodeStyle" ;;
            mongodb)        FLAGS="-PonlyMongodbTests -PskipCodeStyle" ;;
            redis)          FLAGS="-PonlyRedisTests -PskipCodeStyle" ;;
            neo4j)          FLAGS="-PonlyNeo4jTests -PskipCodeStyle" ;;
            springsecurity) FLAGS="-PonlySpringSecurityTests -PskipCodeStyle" ;;
            *) fail "all-suites: lane desconocido '${LANE}'" ;;
        esac
        ARGS="check --continue ${FLAGS}"
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
    task)
        # Cualquier tarea de Gradle: `tasks` es la línea de comandos completa,
        # p.ej. ":grails-core:dependencyInsight --dependency x --configuration runtimeClasspath".
        [[ -n "${TASKS}" ]] || fail "el perfil task requiere el input tasks"
        ARGS="${TASKS}"
        ;;
    fix)
        # Arregla violaciones de CodeNarc de los módulos indicados. El
        # codenarcFix del repo reescribe TODOS los .groovy del proyecto
        # (incluidos test sources que el chequeo no mira), así que a nivel raíz
        # produce un parche enorme; por eso exige `modules`. Para el repo
        # completo, a sabiendas: `task tasks=codenarcFix`.
        [[ -n "${MODULES}" ]] ||
            fail "el perfil fix requiere modules (a nivel raíz reescribe todo el repo; usa task tasks=codenarcFix si lo quieres entero)"
        FIX_TASKS=""
        for m in ${MODULES}; do FIX_TASKS="${FIX_TASKS} ${m}:codenarcFix"; done
        ARGS="${FIX_TASKS} --continue"
        ;;
    *)
        fail "perfil desconocido: '${PROFILE}'"
        ;;
esac

# `extra` va al final a propósito: puede añadir tareas y flags que ganan a los
# del perfil (p.ej. --tests, --rerun-tasks, -PmaxTestParallel=1).
CMD="./gradlew ${ARGS} ${EXTRA} --stacktrace"

echo "::notice::ref=${REF:-?} perfil=${PROFILE}${LANE:+ lane=${LANE}}${SUBDIR:+ subdir=${SUBDIR}}"
echo "::group::comando"
echo "${CMD}"
echo "::endgroup::"

set +e
# shellcheck disable=SC2086
${CMD}
status=$?
set -e

# Los fixers (codenarcFix, spotlessApply) modifican el árbol y el runner es
# efímero: se publica el parche para poder aplicarlo en local (artefacto
# `changes.patch`), y se deja constancia en el log aunque no haya cambios.
status_output=$(git status --porcelain 2>/dev/null || true)
changed=$(grep -c . <<<"${status_output}" || true)
if (( changed > 0 )); then
    git add -A -N >/dev/null 2>&1 || true
    git diff >"${GITHUB_WORKSPACE}/changes.patch" || true
    patch_kb=$(( $(stat -c%s "${GITHUB_WORKSPACE}/changes.patch" 2>/dev/null || echo 0) / 1024 ))
    echo "::warning::la ejecución dejó ${changed} ruta(s) modificada(s); changes.patch (${patch_kb} KB) en los artefactos"
    if (( patch_kb > 200 )); then
        echo "::warning::parche grande (${patch_kb} KB): ¿seguro que querías un fixer a nivel de todo el repo?"
    fi
    # sed lee toda la entrada: `head` cerraría el pipe y con set -e mataría el script.
    sed -n '1,40p' <<<"${status_output}"
else
    rm -f "${GITHUB_WORKSPACE}/changes.patch"
fi

exit "${status}"
