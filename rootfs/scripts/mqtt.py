#!/usr/bin/python3
'''
# -----------------------------------------------------------------------------------
# Copyright 2020-2025 Ramon F. Kolb - licensed under the terms and conditions
# of GPLv3. The terms and conditions of this license are included with the Github
# distribution of this package, and are also available here:
# https://github.com/sdr-enthusiasts/docker-planefence/
#
# -----------------------------------------------------------------------------------
#

Send a message to a MQTT broker
Syntax: mqtt.py --broker <broker_ip> [--port <port>] --topic <topic> --qos <qos> --client_id <client_id> --message <message>
where:
--broker: The address of the MQTT broker.
--port: The port of the MQTT broker (default is 1883).
--topic: The topic to which the message will be published.
--qos: The Quality of Service level (0, 1, or 2).
--message: The message payload to publish.
--client_id: The MQTT client identifier.
'''

import argparse
import paho.mqtt.client as mqtt # type: ignore

def publish_message(broker, port, topic, qos, message, client_id, username=None, password=None):
    # Create an MQTT client instance
    client = mqtt.Client(client_id)

    # Set username and password if provided
    if username and password:
        client.username_pw_set(username, password)

    try:
        # Connect to the MQTT broker
        client.connect(broker, port)
        # Publish the message
        client.publish(topic, payload=message, qos=qos)
        print(f"Message '{message}' published to topic '{topic}' with QoS {qos}.")
        # Disconnect from the broker
        client.disconnect()
    except Exception as e:
        print(f"Failed to publish message: {e}")

def main():
    # Set up command-line arguments
    parser = argparse.ArgumentParser(description="MQTT Publish Command Line Tool")
    parser.add_argument("--broker", required=True, help="MQTT broker address (e.g., 'localhost').")
    parser.add_argument("--port", type=int, default=1883, help="MQTT broker port (default: 1883).")
    parser.add_argument("--topic", required=True, help="MQTT topic to publish to.")
    parser.add_argument("--qos", type=int, choices=[0, 1, 2], default=0, help="Quality of Service level (default: 0).")
    parser.add_argument("--message", required=True, help="Message to publish.")
    parser.add_argument("--client_id", default="mqtt_client", help="Client ID for MQTT connection (default: 'mqtt_client').")
    parser.add_argument("--username", help="Username for MQTT authentication.")
    parser.add_argument("--password", help="Password for MQTT authentication.")
    args = parser.parse_args()

    # Publish the message
    publish_message(
        broker=args.broker,
        port=args.port,
        topic=args.topic,
        qos=args.qos,
        message=args.message,
        client_id=args.client_id,
        username=args.username,
        password=args.password,
    )

if __name__ == "__main__":
    main()
