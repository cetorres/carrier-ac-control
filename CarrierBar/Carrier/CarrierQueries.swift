import Foundation

/// GraphQL documents sent to Carrier. Field names match what the Carrier apps request.
enum CarrierQueries {
    static let assistedLogin = """
    mutation assistedLogin($input: AssistedLoginInput!) {
      assistedLogin(input: $input) {
        success
        status
        errorMessage
        data {
          token_type
          expires_in
          access_token
          scope
          refresh_token
        }
      }
    }
    """

    static let infinitySystems = """
    query getInfinitySystems($userName: String!) {
      infinitySystems(userName: $userName) {
        profile {
          serial
          name
          firmware
          model
          brand
          indoorModel
          outdoorModel
          idutype
          odutype
        }
        status {
          localTime
          isDisconnected
          cfgem
          mode
          oat
          filtrlvl
          odu { type opstat }
          idu { type opstat }
          zones {
            id
            rt
            rh
            fan
            htsp
            clsp
            hold
            enabled
            currentActivity
            zoneconditioning
          }
        }
        config {
          zones {
            id
            name
            enabled
            hold
            holdActivity
            otmr
            program {
              id
              day {
                id
                period {
                  id
                  activity
                  time
                  enabled
                }
              }
            }
            activities {
              id
              type
              fan
              htsp
              clsp
            }
          }
        }
      }
    }
    """

    /// Sets the setpoints and fan of a zone's "manual" activity.
    static let updateInfinityZoneActivity = """
    mutation updateInfinityZoneActivity($input: InfinityZoneActivityInput!) {
      updateInfinityZoneActivity(input: $input) {
        etag
      }
    }
    """

    /// Puts a zone on hold in an activity (the manual one, or a comfort profile like "away"),
    /// or turns the hold off so the zone follows its schedule again.
    static let updateInfinityZoneConfig = """
    mutation updateInfinityZoneConfig($input: InfinityZoneConfigInput!) {
      updateInfinityZoneConfig(input: $input) {
        etag
      }
    }
    """

    /// Changes system wide Infinity settings, like the mode.
    static let updateInfinityConfig = """
    mutation updateInfinityConfig($input: InfinityConfigInput!) {
      updateInfinityConfig(input: $input) {
        etag
      }
    }
    """

    /// Changes a Smart Thermostat zone. Setpoints go together; mode and fan can go on their own.
    static let updateEntryLevelZone = """
    mutation updateEntryLevelZone($input: EntryLevelZoneInput!) {
      updateEntryLevelZone(input: $input) {
        success
      }
    }
    """

    static let entryLevelSystems = """
    query getEntryLevelSystems($username: String!) {
      entryLevelSystems(username: $username) {
        serial
        name
        model
        firmware
        temp_unit_format
        timezone
        connection {
          isConnected
          deviceId
        }
        zones {
          index
          mode
          rt
          rh
          clsp { current }
          htsp { current }
          fan_mode
          schedule_enabled
          stage_status
          outside_temp
          current_scene_name
          hold_end_time
          hold_countdown
          schedule {
            scene_name
            start_time
            day
          }
          comfort_profile {
            wake { htsp clsp }
            home { htsp clsp }
            away { htsp clsp }
            sleep { htsp clsp }
          }
        }
      }
    }
    """
}
