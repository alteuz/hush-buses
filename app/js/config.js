// Supabase connection used by the web system and the Cordova app.
// The publishable (anon) key is safe to ship: Row Level Security only allows
// reads, and every write goes through the api_* SQL functions.
window.CUNDIBUS_CONFIG = {
  supabaseUrl: 'https://tjhchuxmkcjvwetxrowo.supabase.co',
  supabaseKey: 'sb_publishable_WwaB1Q9u-mWOXiDBEq8Mpw_aCzOKgwI',
  timeZone: 'America/Bogota',
  refreshSeconds: 30,
  // Bounding box of Cundinamarca (lng/lat) used to bias geocoding.
  viewbox: [-74.90, 5.84, -73.05, 3.73]
};
