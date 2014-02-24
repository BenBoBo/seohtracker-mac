// Mainly NSUserDefaults wrappers.

float bundle_version(void);
bool system_uses_metric(void);

float config_changelog_version(void);
void set_config_changelog_version(float value);

int user_metric_preference(void);
void set_user_metric_preference(int value);
