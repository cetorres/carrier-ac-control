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
          }
        }
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
        }
      }
    }
    """
}
