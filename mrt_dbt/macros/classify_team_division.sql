/*
  classify_team_division -- TEAM_DIVISION 분류 매크로

  DIM_RESVE_TYPE/DIM_PRODUCT_TYPE 공통 사용. 단일 로직 (model_type 분기 제거).
  resve_type/hocance_offer_id/trimo_res_id 파라미터 유무로 모델별 조건 자동 분기.

  주요 파라미터:
  - domain_nm, partner_id, product_id, guide_id, biz_type 등 (분류 조건 컬럼)
  - hocance_offer_id: RESVE 전용 (PRODUCT는 none)
  - trimo_res_id: RESVE 전용 (PRODUCT는 none)
  - resve_type: RESVE 전용 (PRODUCT는 none)
*/
{% macro classify_team_division(
    domain_nm,
    partner_id,
    product_id,
    guide_id,
    biz_type,
    offer_type,
    offer_id,
    offer_guide_id,
    product_type,
    sub_category_cd,
    vehicle_id,
    hocance_offer_id=none,
    trimo_res_id=none,
    resve_type=none
) %}

{% set _ticket_lodging_ids = ticket_lodging_ids() %}
{% set _new_biz_guide_ids = new_biz_guide_ids() %}

CASE
    {# ================================================================== #}
    {# 1. flight / insurance / bdka -- flight 최상위 (#5 통합)             #}
    {# ================================================================== #}
    WHEN ({{ domain_nm }} = 'AIR' OR {{ partner_id }} = '100525') THEN 'flight'
    WHEN {{ domain_nm }} = 'INSURANCE' THEN 'insurance'
    WHEN {{ guide_id }} IS NOT NULL AND {{ biz_type }} = 'Key Accounts' THEN 'bdka'

    {# ================================================================== #}
    {# 2. accommodation -- 통합 + 괄호 명확화 (#10)                        #}
    {# ================================================================== #}
    WHEN ({{ domain_nm }} = 'HOTEL')
        OR ({{ offer_type }} IN ('Lodging', 'Pension'))
        OR (UPPER({{ product_type }}) = 'ACCOMMODATION')
        {% if resve_type is not none %}
        OR ({{ resve_type }} = 'accommodation')
        {% endif %}
        {% if hocance_offer_id is not none %}
        OR ({{ hocance_offer_id }} IS NOT NULL)
        {% endif %}
        OR ({{ guide_id }} IS NOT NULL AND {{ biz_type }} = 'Hotel')
        OR ({{ domain_nm }} = '2.0 PRODUCT' AND (
            {% if resve_type is not none %}{{ resve_type }} = 'hotel' OR {% endif %}
            {{ offer_type }} = 'Hotel'
        ))
        OR ({{ product_id }} IN ('{{ _ticket_lodging_ids | join("', '") }}'))
        OR ({{ sub_category_cd }} = 'my_real_hotel')
        THEN 'accommodation'

    {# ================================================================== #}
    {# 3. transport -- TRIMO 조건은 trimo_res_id 전달 시에만 포함           #}
    {# ================================================================== #}
    WHEN ({{ guide_id }} IS NOT NULL AND {{ biz_type }} IN ('Car rental', 'Other trans'))
        OR ({{ offer_id }} = 100600)
        OR ({{ vehicle_id }} IS NOT NULL)
        {% if trimo_res_id is not none %}
        OR ({{ trimo_res_id }} IS NOT NULL)
        {% endif %}
        THEN 'transport'

    {# ================================================================== #}
    {# 4. new_biz -- 공통                                                  #}
    {# ================================================================== #}
    WHEN ({{ offer_type }} = 'HotDeal')
        OR ({{ offer_guide_id }} IN ({{ _new_biz_guide_ids | join(', ') }}))
        THEN 'new_biz'

    {# ================================================================== #}
    {# 5. bdx -- 2.0 + 3.0 모두 (#4 통합)                                 #}
    {# ================================================================== #}
    WHEN {{ domain_nm }} IN ('2.0 PRODUCT', '3.0 PRODUCT') THEN 'bdx'

    ELSE 'unclassified'
END
{% endmacro %}
