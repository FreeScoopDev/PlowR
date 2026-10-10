### Changed
- Weather comes from Apple's WeatherKit instead of Open-Meteo: current
  conditions, the 7-day forecast and snowfall the storm card uses, and the
  Service Report's weather for past visit days. Open-Meteo's free service
  is for non-commercial apps only, and an app with a subscription is
  commercial, so it couldn't be used once PlowR Pro goes on sale; its paid
  plan with the history the Service Report needs would have been a monthly
  cost. WeatherKit comes with the Apple developer membership and keeps PlowR
  free of third-party code. Locations sent are still rounded to about 1 km.
  Apple's attribution (the Apple Weather mark and a Data Sources link) shows
  under the weather on the Dashboard, the route screen and the Schedule,
  and the Service Report credits it with Apple's legal page.
- The evening weather alert also counts a day with 0.1 in or more of
  precipitation, whatever its label: WeatherKit describes a day as a whole,
  not its worst hour. Windy, hot, hazy and smoky days get their own labels.
