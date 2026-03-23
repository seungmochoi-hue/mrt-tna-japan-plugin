{% docs __overview__ %}
# dbt 프로젝트 개요

```
MyRealTrip의 데이터 파이프라인을 관리하기 위해 dbt를 사용하여 구축되었습니다.
dbt는 데이터 변환 및 모델링을 위한 강력한 도구로, SQL을 사용하여 데이터 파이프라인을 정의하고 실행할 수 있습니다.
```


## [dbt 공식 문서](https://docs.getdbt.com/docs/introduction)
## [마리트 위키](https://myrealtrip.atlassian.net/wiki/spaces/DP/pages/4430692414/dbt)
## [작성 규칙](https://myrealtrip.atlassian.net/wiki/spaces/DP/pages/4453269960)
## [dbt docs 사용법](https://myrealtrip.atlassian.net/wiki/spaces/DP/pages/4530339847/Docs)

### [용어사전](https://docs.google.com/spreadsheets/d/1PX5U6Tyh6vph5-AS8AhTfzcWmfRViSdOOQs8DaB-cgU/edit?gid=1490010155#gid=1490010155)


## 프로젝트 구조
이 프로젝트는 다음과 같은 디렉토리 구조를 가지고 있습니다

- `models/`: 데이터 모델을 정의하는 SQL 파일이 포함되어 있습니다.
- `macros/`: 재사용 가능한 SQL 코드를 정의하는 매크로가 포함되어 있습니다.
- `tests/`: 데이터 품질 테스트를 정의하는 SQL 파일이 포함되어 있습니다.
- `dbt_project.yml`: dbt 프로젝트 설정 파일입니다.
- `profiles.yml`: dbt 프로필 설정 파일입니다.
- `packages.yml`: dbt 패키지 의존성을 정의하는 파일입니다.


models 디렉토리에는 다음과 같은 하위 디렉토리가 있습니다:
- `staging/`: 소스 데이터를 추출하고 변환하는 단계입니다.
- `marts/`: 마트 테이블 및 비즈니스 로직을 정의하는 단계입니다.





{% enddocs %}