/*
  _classification_constants -- classify_mrt_type / classify_team_division 공용 상수 매크로

  분류 매크로에서 공통으로 사용하는 ID 목록과 카테고리 목록을 한 곳에서 관리한다.
  변경 시 이 파일만 수정하면 양쪽 매크로에 동시 반영된다.
*/

{% macro ticket_lodging_ids() %}
{% set ids = [
    '102703', '103491', '103644', '104056', '104288', '104161', '104455',
    '104492', '104592', '104620', '104655', '104862', '105226', '105290',
    '105318', '105442', '105571'
] %}
{{ return(ids) }}
{% endmacro %}

{% macro hotel_categories() %}
{% set cats = [
    'hotel', 'resort', 'condominium', 'residence',
    'hotel_v2', 'capsule_hotel', 'aparthotel',
    'resort_v2', 'condominium_resort', 'condo', 'all_inclusive_property',
    'apartment_v2', 'serviced_apartment', 'residence_v2', 'townhouse',
    'hostel', 'guest_house_v2', 'hostal', 'home_stay', 'hostel_backpacker', 'bed_and_breakfast',
    'motel_v2', 'inn'
] %}
{{ return(cats) }}
{% endmacro %}

{% macro pension_exclude() %}
{% set cats = ['lodging'] + hotel_categories() %}
{{ return(cats) }}
{% endmacro %}

{% macro ticket_rentalcar_partner_ids() %}
{% set ids = ['14627', '15150', '10508', '16663'] %}
{{ return(ids) }}
{% endmacro %}

{% macro new_biz_guide_ids() %}
{% set ids = [12718, 13678, 13165, 13638, 13450] %}
{{ return(ids) }}
{% endmacro %}
