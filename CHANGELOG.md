cookbook-airflow CHANGELOG
===============

## 0.3.0

  - Rafa Gómez
    - [0545f94] Feature/#23213 Make dag processor and airflow triggerer cluster compatible (#8)

## 0.2.0

  - Rafa Gómez
    - [18752c7] Feature/#23083 Make airflow compatible with a cluster-node environment (#5)

## 0.1.0

  - vimesa
    - [bfc572c] Fix the error when disabling Airflow.
    - [9445d97] Add new package redborder-malware-pythonpyenv
  - Rafael Gomez
    - [643187f] Remove unnecessary block
    - [c475f22] Change simple_auth_manager_passwords.json to be created at /opt/airflow, fix remove directory airflow_env_dir and register airflow web with the mgt ip
    - [880d4e5] Enable authenticaction and put automatic authenticaction to False
    - [3484dc0] Remove unused vairable to pass linter
    - [e1007ce] Using the magement ip instead of the sync in the base url
