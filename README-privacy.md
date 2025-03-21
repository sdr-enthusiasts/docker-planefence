# Docker-Planefence Privacy Statement and Policy

- [Docker-Planefence Privacy Statement and Policy](#docker-planefence-privacy-statement-and-policy)
  - [Data Handling and Privacy Notice](#data-handling-and-privacy-notice)
  - [Definitions](#definitions)
  - [Privacy and Data Use](#privacy-and-data-use)
  - [Inspection of Implementation of Data Use Policies](#inspection-of-implementation-of-data-use-policies)
  - [Contact Information for Data Use and Privacy Questions and Issues](#contact-information-for-data-use-and-privacy-questions-and-issues)

## Data Handling and Privacy Notice

This Privacy Notice is to inform EU and U.K. citizens who use the `sdr-enthusiasts/docker-planefence` container how their personal information is used, in compliance with GDPR regulations. However, our Data Use and Privacy policy is world-wide and apply to all Planefence users regardless of their location.

## Definitions

- **Planefence**: the suite of software that is downloaded and deployed via the `sdr-enthusiasts/docker-planefence` Docker container, including all labeled and non-labeled versions. This suite of software includes features like planefence (to monitor aircraft in a radius around a specific location), plane-alert (to monitor interesting aircraft in range of your receiver), and software to help implementing this suite, create notifications, etc.
- **You**: the owner or operator of the hardware on which the `docker-planefence` container runs
- **We**, **Us**, or **Our**: the authors and contributors to the planefence software
- **Personal Data**: Any information relating to an identified or identifiable natural person, as meant under the GDPR. For US users, Personal Data includes "Personally Identifiable Information" as defined by NIST.

## Privacy and Data Use

Planefence runs on hardware that You own or control, and the configuration options that You provide via the `docker-compose.yml` file, the `planefence.config` file, etc. are used on your device for the execution of Planefence. Planefence's web pages do not include any trackers or other features meant to externally track your usage or Personal Data.

Planefence may connect to external services to retrieve data that is important to render its features and functionality. As part of this connection, it may provide (but is not limited to) your IP address, information about your hardware, the software build and package version of Planefence, and the name of the Planefence instance that you configured using the `PF_NAME` parameter. Examples of external services include but are not limited to: <github.com> and <planespotters.net>. If you configure notifications to be sent externally (for example, to Discord, BlueSky, MQTT, etc.), your data, including the login credentials that you have configured for these notification services, will be sent to these notification providers. The use of this data by these external services is outside Our span of control and is governed by the respective license or use terms, privacy policies, and data use policies of these external services. Although the use of some of these external services may be configurable, the only way to guarantee that this data is not shared with *any* external services is by stopping, removing, and ceasing to use Planefence.

Since We do not operate any of these external services, We do not receive any Personal Data from You, even though these external service may receive Personal Data from You.

## Inspection of Implementation of Data Use Policies

Planefence is an Open Source product, and the code can be found at its Github repository <https://sdr-e.com/docker-planefence>. You may inspect it there if you are interested in further details of the data use by Planefence.

## Contact Information for Data Use and Privacy Questions and Issues

The contact information for data privacy related questions and issues is <privacy (at) kx1t (dot) com>, or by Snail Mail to KX1T - Privacy Issues, PO Box 11, Belmont MA 02478. If your question is generic and non-confidential, you can also file an Issue at Planefence's [Github Repository](https://sdr-e.com/docker-planefence/issues).
