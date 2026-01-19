#!/usr/bin/python3
'''
# -----------------------------------------------------------------------------------
# Copyright 2020-2026 Ramon F. Kolb - licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/sdr-enthusiasts/docker-planefence/
#
# -----------------------------------------------------------------------------------
#

Send a message to a MQTT broker
Syntax: mqtt.py --broker <broker_ip> [--port <port>] --topic <topic> --qos <qos> --client_id <client_id> --message <message> [--tls]
where:
--broker: The address of the MQTT broker.
--port: The port of the MQTT broker (default is 1883, use 8883 for TLS).
--topic: The topic to which the message will be published.
--qos: The Quality of Service level (0, 1, or 2).
--message: The message payload to publish.
--client_id: The MQTT client identifier.
--tls: Enable TLS encryption.
'''

import argparse
import ssl
import paho.mqtt.publish as publish

def main():
    # Set up command-line arguments
    parser = argparse.ArgumentParser(description="MQTT Publish Command Line Tool")
    parser.add_argument("--broker", required=True, help="MQTT broker address (e.g., 'localhost').")
    parser.add_argument("--port", type=int, default=1883, help="MQTT broker port (default: 1883, use 8883 for TLS).")
    parser.add_argument("--topic", required=True, help="MQTT topic to publish to.")
    parser.add_argument("--qos", type=int, choices=[0, 1, 2], default=0, help="Quality of Service level (default: 0).")
    parser.add_argument("--message", required=True, help="Message to publish.")
    parser.add_argument("--client_id", default="mqtt_client", help="Client ID for MQTT connection (default: 'mqtt_client').")
    parser.add_argument("--username", help="Username for MQTT authentication.")
    parser.add_argument("--password", help="Password for MQTT authentication.")
    parser.add_argument("--tls", action="store_true", help="Enable TLS encryption.")

    args = parser.parse_args()

    # If port is 8883, assume TLS is wanted even if flag is missing
    enable_tls = args.tls or args.port == 8883

    # Publish the message
    try:
        publish.single(topic=args.topic, payload=args.message, qos=args.qos, retain=True, hostname=args.broker, port=args.port, client_id=args.client_id, **({"auth":{'username':args.username, 'password':args.password}} if not args.username or args.password else {}), **({"tls":ssl.create_default_context()} if args.tls else {}))
        print(f"Message '{args.message}' published to topic '{args.topic}' with QoS {args.qos}.")
    except Exception as e:
        print(f"Failure in publishing message!")

if __name__ == "__main__":
    main()
