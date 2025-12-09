SELECT
  SUM(`tfuka_memudedet`) AS total_tfuka
FROM
  `bidata_prod`.`std`.`dwh_hareldwh_shivuk_dwh_fact_shivuk_agg_by_model_adb_liquid_managed_rls`
WHERE
  `month_tfuka` = 202501
  AND `businesssubject_kibutzal_desc` LIKE '%סיכוני פרט%'
  AND `mefakeachal_name` LIKE '%דורון נגר%'
  AND `makor` IN ('TfukaBitulim', 'גמל', 'Niyud Gemel', 'Pensia', 'Prisha_Miyadit', 'HUL', 'Migvan')


 Generated query was invalid
Genie created a query that could not be executed successfully. You can try to rephrase your question or contact the owner of this space to add more specific instructions. If this issue persists please contact your Databricks account team.
Genie tried to generate a running query 3 times but could not resolve the error automatically.
SQL error: [QUERY_RESULT_WRITE_TO_CLOUD_STORE_PERMISSION_ERROR] The workspace internal storage configuration prevents Databricks from accessing the cloud store. SQLSTATE: 42501
