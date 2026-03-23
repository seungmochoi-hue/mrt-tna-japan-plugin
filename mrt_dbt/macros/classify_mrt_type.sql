/*
  classify_mrt_type -- MRT_TYPE 분류 매크로

  DIM_RESVE_TYPE/DIM_PRODUCT_TYPE 공통 사용. 단일 로직 (model_type 분기 제거).
  resve_type/standard_category_lv_3_cd/trimo_res_id 파라미터 유무로 모델별 조건 자동 분기.

  주요 파라미터:
  - product_id, domain_nm, partner_id, product_category 등 (분류 조건 컬럼)
  - rentalcar_check_id: RESVE는 PARTNER_ID, PRODUCT는 GID (미지정 시 partner_id)
  - resve_type: RESVE 전용 (PRODUCT는 '' 전달)
  - standard_category_lv_3_cd: PRODUCT 전용 (RESVE는 '' 전달)
  - trimo_res_id: RESVE 전용 (PRODUCT는 '' 전달)

  3.0 T&A fallback:
  - offer_type이 NULL인 3.0 상품에 대해 STANDARD_CATEGORY_LV_2_CD 기반으로 tour/ticket 분류
  - _ta_tour_categories: GUIDE_TOUR, PACKAGE_TOUR
  - _ta_ticket_categories: ADMISSION_TICKET 등 13개 카테고리
*/

{% macro classify_mrt_type(
    product_id,
    domain_nm,
    partner_id,
    resve_type,
    offer_type,
    offer_title,
    product_title,
    product_category,
    product_type,
    sub_category_cd,
    category_cd,
    standard_category_lv_2_cd,
    rentalcar_check_id='',
    standard_category_lv_3_cd='',
    trimo_res_id='',
    offer_scale=''
) %}

/* rentalcar_check_id 미지정 시 partner_id를 기본값으로 사용 */
{% set _rentalcar_check_id = rentalcar_check_id if rentalcar_check_id else partner_id %}

{% set _ticket_lodging_ids = ticket_lodging_ids() %}
{% set _ticket_rentalcar_partner_ids = ticket_rentalcar_partner_ids() %}
{% set _ticket_rentalcar_product_id = '100600' %}
{% set _hotel_categories = hotel_categories() %}
{% set _pension_exclude = pension_exclude() %}
{% set _standard_category_lv_2_list = ['HOTELS', 'RESORTS', 'HOSTELS', 'APARTMENTS', 'MOTELS'] %}
{% set _ta_tour_categories = ['GUIDE_TOUR', 'PACKAGE_TOUR'] %}
{% set _ta_ticket_categories = [
    'ADMISSION_TICKET', 'BEAUTY_TICKET', 'GOURMET_TICKET', 'SHOW_TICKET',
    'GROUND_ACTIVITY', 'WATER_ACTIVITY', 'AQUATIC_ACTIVITY', 'SKY_ACTIVITY',
    'CLASSES', 'USIM_WIFI', 'SNAPS', 'ETC_CONVENIENCES', 'PICKUP_SENDINGS'
] %}

CASE
    -- ticket_rentalcar: 특정 파트너(또는 GID) 또는 상품 ID
    WHEN {{ _rentalcar_check_id }} IN ('{{ _ticket_rentalcar_partner_ids | join("', '") }}')
    OR {{ product_id }} = '{{ _ticket_rentalcar_product_id }}' THEN 'ticket_rentalcar'

    -- ticket_lodging: 특정 상품 ID 목록 또는 서브카테고리
    WHEN {{ product_id }} IN ('{{ _ticket_lodging_ids | join("', '") }}')
    OR {{ sub_category_cd }} = 'my_real_hotel' THEN 'ticket_lodging'

    -- tour (랜선투어): 특정 파트너 + 타이틀에 '랜선' 포함
    WHEN {{ partner_id }} = '12718' AND ({{ offer_title }} LIKE '%랜선%' OR {{ product_title }} LIKE '%랜선%') THEN 'tour'

    -- kids: 카테고리 코드
    WHEN {{ category_cd }} = 'kids' THEN 'kids'

    -- ticket_flight: 특정 파트너 ID
    WHEN {{ partner_id }} = '100525' THEN 'ticket_flight'

    -- ticket (2.0): resve_type 또는 offer_type 기준
    WHEN {{ domain_nm }} = '2.0 PRODUCT' AND (
        {% if resve_type %}{{ resve_type }} IN ('deliveryticket', 'eticket', 'istanbulticket', 'ticket') OR {% endif %}
        LOWER({{ offer_type }}) IN ('deliveryticket', 'eticket', 'istanbulticket', 'ticket')
    ) THEN 'ticket'

    -- hotdeal (2.0): resve_type 또는 offer_type 기준
    WHEN {{ domain_nm }} = '2.0 PRODUCT' AND (
        {% if resve_type %}{{ resve_type }} = 'hotdeal' OR {% endif %}
        LOWER({{ offer_type }}) = 'hotdeal'
    ) THEN 'hotdeal'

    -- hotdeal (3.0): offer_type 기준
    WHEN {{ domain_nm }} = '3.0 PRODUCT' AND LOWER({{ offer_type }}) = 'hotdeal' THEN 'hotdeal'

    -- lodging: product_category + standard_category_lv_3_cd 통합
    WHEN ({{ domain_nm }} = '3.0 PRODUCT' AND (
        LOWER({{ product_category }}) IN ('lodging', 'lodging_v2', 'lodge_v2')
        {% if standard_category_lv_3_cd %}
        OR {{ standard_category_lv_3_cd }} IN ('LODGING_V2', 'LODGE_V2')
        {% endif %}
    ))
    OR ({{ domain_nm }} = '2.0 PRODUCT' AND (
        {% if resve_type %}{{ resve_type }} = 'lodging' OR {% endif %}
        LOWER({{ offer_type }}) = 'lodging'
    )) THEN 'lodging'

    -- pension: lodging 계열 + hotel 계열 제외
    WHEN ({{ domain_nm }} = '2.0 PRODUCT' AND (
        {% if resve_type %}{{ resve_type }} = 'pension' OR {% endif %}
        LOWER({{ offer_type }}) = 'pension'
    ))
    OR ({{ domain_nm }} = '3.0 PRODUCT' AND LOWER({{ product_type }}) = 'accommodation'
        AND (
            LOWER({{ product_category }}) NOT IN ('{{ _pension_exclude | join("', '") }}')
            AND {{ standard_category_lv_2_cd }} NOT IN ('{{ _standard_category_lv_2_list | join("', '") }}')
        )
    ) THEN 'pension'

    -- tour (2.0): resve_type 또는 offer_type 기준 (private_tour fallback 제거)
    WHEN {{ domain_nm }} = '2.0 PRODUCT' AND (
        {% if resve_type %}{{ resve_type }} = 'tour' OR {% endif %}
        LOWER({{ offer_type }}) = 'tour'
    ) THEN 'tour'

    -- rentalcar: product_category + standard_category_lv_3_cd + TRIMO
    WHEN ({{ domain_nm }} = '3.0 PRODUCT' AND (
        LOWER({{ product_category }}) IN ('renter_car', 'rent_a_car')
        {% if standard_category_lv_3_cd %}
        OR {{ standard_category_lv_3_cd }} = 'RENT_A_CAR'
        {% endif %}
    ))
    {% if trimo_res_id %}
    OR ({{ trimo_res_id }} IS NOT NULL)
    {% endif %}
    THEN 'rentalcar'

    -- hotel: HOTEL 도메인 + 2.0 hotel + 3.0 숙소 카테고리
    WHEN ({{ domain_nm }} = 'HOTEL')
    OR ({{ domain_nm }} = '2.0 PRODUCT' AND (
        {% if resve_type %}{{ resve_type }} = 'hotel' OR {% endif %}
        LOWER({{ offer_type }}) = 'hotel'
    ))
    OR ({{ domain_nm }} = '3.0 PRODUCT' AND LOWER({{ product_type }}) = 'accommodation'
        AND (
            LOWER({{ product_category }}) IN ('{{ _hotel_categories | join("', '") }}')
            OR {{ standard_category_lv_2_cd }} IN ('{{ _standard_category_lv_2_list | join("', '") }}')
        )
    ) THEN 'hotel'

    -- insurance: INSURANCE 도메인
    WHEN {{ domain_nm }} = 'INSURANCE' THEN 'insurance'

    -- flight: AIR 도메인
    WHEN {{ domain_nm }} = 'AIR' THEN 'flight'

    -- ticket (3.0 T&A): touractivity 연동 또는 offer_type 기반
    WHEN {{ domain_nm }} = '3.0 PRODUCT'
        {% if resve_type %}AND {{ resve_type }} = 'touractivity'{% endif %}
        AND {{ offer_type }} IS NOT NULL
        AND LOWER({{ offer_type }}) IN ('deliveryticket', 'eticket', 'istanbulticket', 'ticket') THEN 'ticket'

    -- tour (3.0 T&A): touractivity 연동 또는 offer_type 기반
    WHEN {{ domain_nm }} = '3.0 PRODUCT'
        {% if resve_type %}AND {{ resve_type }} = 'touractivity'{% endif %}
        AND LOWER({{ offer_type }}) = 'tour' THEN 'tour'

    -- tour (3.0 T&A fallback): STANDARD_CATEGORY_LV_2_CD 기반
    WHEN {{ domain_nm }} = '3.0 PRODUCT'
        AND {{ offer_type }} IS NULL
        AND {{ standard_category_lv_2_cd }} IN ('{{ _ta_tour_categories | join("', '") }}')
        THEN 'tour'

    -- ticket (3.0 T&A fallback): STANDARD_CATEGORY_LV_2_CD 기반
    WHEN {{ domain_nm }} = '3.0 PRODUCT'
        AND {{ offer_type }} IS NULL
        AND {{ standard_category_lv_2_cd }} IN ('{{ _ta_ticket_categories | join("', '") }}')
        THEN 'ticket'

    ELSE 'unclassified'
END

{% endmacro %}
