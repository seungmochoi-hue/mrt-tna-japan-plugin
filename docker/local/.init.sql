-- 기존 데이터베이스 삭제
DROP DATABASE IF EXISTS mrtdata;

-- 새로운 데이터베이스 생성
CREATE DATABASE mrtdata;

-- PostgreSQL에서는 `USE mrtdata;`를 사용할 수 없으므로, psql 환경에서는 `\c` 명령어를 직접 입력해야 합니다.
\c mrtdata;
