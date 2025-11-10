# Script for continuous deployment

arguments :

REPO_LOCATION= the project loation on host

DOCKER_COMPOSE_RESTART_REQUIRED= yes or no

Optional :

CI_PEPLINE_LOCATION=

# If non standard redeploy script to be executed
CUSTOM_REDEPLOY_SCRIPT_LOCATION= location on system




Script flow:

if CUSTOM_REDEPLOY_SCRIPT_LOCATION provided,
    we skip our script and execute the script at the provided location

else:

    - we copy the project into a temporary location for backup
    - Then we run git pull from repo location
    (we expect a deploy key setup, so auth is automatic)

    if CI_PEPLINE_LOCATION= provided :

        - we run the provided tes script

        if test pass, good exit code:
            pass continue with our script

        else (test script fails, error ):
            - mv our backup file back into project position
            - explicit failure, interupt the redeploy process



    if DOCKER_COMPOSE_RESTART_REQUIRED=YES:
        - we run docker compose down
        - and then docker compose --build --force-recreate

