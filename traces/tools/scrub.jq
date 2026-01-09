# 1) Redact Iceberg / filesystem split paths
def scrub_split_paths:
  (.. | objects
      | select(has("splitInfo") and (.splitInfo | has("path")))
      | .splitInfo.path) = "<REDACTED_SPLIT_PATH>";

# 2) Redact tableLocation (Iceberg connector handle)
def scrub_table_location:
  (.. | objects
      | select(has("tableLocation"))
      | .tableLocation) = "<REDACTED_TABLE_LOCATION>";

# 3) Remove remote user IPs
def scrub_remote_user_address:
  del(.. | .remoteUserAddress?);

# 4) Remove internal service URLs
def scrub_self_uri:
  del(.. | .self?);

# 5) Delete timestamps
def scrub_any_iso_timestamps:
  walk(
    if type == "object" then
      with_entries(
        select(
          .value
          | (type != "string")
          or (test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})?$") | not)
        )
      )
    else .
    end
  );

scrub_split_paths
| scrub_table_location
| scrub_remote_user_address
| scrub_self_uri
| scrub_any_iso_timestamps
