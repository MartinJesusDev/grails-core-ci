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
                ;;
            *) fail "subbuild: dir desconocido '${SUBDIR}'" ;;
        esac
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
