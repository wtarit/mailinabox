#!/usr/local/lib/mailinabox/env/bin/python

import argparse
import smtplib
import socket
import ssl
import sys


PASSWORD_MAP_PATH = "/etc/postfix/sasl_passwd"
VALID_SECURITY = {"starttls", "implicit-tls"}
VALID_USERNAME_CHARACTERS = frozenset("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@._+%=-")


class RelayConfigurationError(ValueError):
	pass


def smtp_relay_enabled(env):
	return env.get("ENABLE_SMTP_RELAY", "0") == "1"


def should_generate_direct_delivery_spf(env):
	return not smtp_relay_enabled(env)


def get_smtp_relay_config(env):
	enabled = smtp_relay_enabled(env)
	config = {
		"enabled": enabled,
		"host": env.get("SMTP_RELAY_HOST", ""),
		"port": env.get("SMTP_RELAY_PORT", "587"),
		"security": env.get("SMTP_RELAY_SECURITY", "starttls"),
		"username": env.get("SMTP_RELAY_USERNAME", ""),
	}
	if enabled:
		validate_smtp_relay_config(config)
		config["host"] = config["host"].encode("idna").decode("ascii").lower()
		config["port"] = int(config["port"])
	return config


def validate_smtp_relay_config(config):
	host = config.get("host", "")
	try:
		ascii_host = host.encode("idna").decode("ascii")
	except UnicodeError as exc:
		raise RelayConfigurationError("SMTP_RELAY_HOST is not a valid hostname.") from exc

	if not ascii_host or len(ascii_host) > 253 or ascii_host.endswith("."):
		raise RelayConfigurationError("SMTP_RELAY_HOST must be a fully-qualified hostname without a trailing period.")
	labels = ascii_host.split(".")
	if len(labels) < 2 or any(
		not label
		or len(label) > 63
		or label.startswith("-")
		or label.endswith("-")
		or any(not (character.isalnum() or character == "-") for character in label)
		for label in labels
	):
		raise RelayConfigurationError("SMTP_RELAY_HOST must be a fully-qualified hostname.")

	try:
		port = int(config.get("port", ""))
	except (TypeError, ValueError) as exc:
		raise RelayConfigurationError("SMTP_RELAY_PORT must be an integer from 1 to 65535.") from exc
	if not 1 <= port <= 65535:
		raise RelayConfigurationError("SMTP_RELAY_PORT must be an integer from 1 to 65535.")

	if config.get("security") not in VALID_SECURITY:
		raise RelayConfigurationError("SMTP_RELAY_SECURITY must be either starttls or implicit-tls.")

	username = config.get("username", "")
	if not username:
		raise RelayConfigurationError("SMTP_RELAY_USERNAME is required when the SMTP relay is enabled.")
	if any(character not in VALID_USERNAME_CHARACTERS for character in username):
		raise RelayConfigurationError("SMTP_RELAY_USERNAME contains unsupported characters.")

	return True


def relay_destination(config):
	return "[{}]:{}".format(config["host"].encode("idna").decode("ascii").lower(), int(config["port"]))


def load_smtp_relay_password(config, password_map_path=PASSWORD_MAP_PATH):
	destination = relay_destination(config)
	try:
		with open(password_map_path, encoding="utf-8") as password_map:
			for line in password_map:
				try:
					map_destination, credentials = line.rstrip("\r\n").split(None, 1)
					username, password = credentials.split(":", 1)
				except ValueError:
					continue
				if map_destination == destination and username == config["username"]:
					return password
	except FileNotFoundError:
		pass
	except (OSError, UnicodeError) as exc:
		raise RelayConfigurationError("Could not read the SMTP relay credentials.") from exc
	raise RelayConfigurationError("SMTP relay credentials are not configured for {}.".format(destination))


def check_smtp_relay(config, password=None, timeout=10):
	validate_smtp_relay_config(config)
	config = dict(config)
	config["port"] = int(config["port"])
	if password is None:
		password = load_smtp_relay_password(config)
	if not password:
		raise RelayConfigurationError("The SMTP relay password cannot be empty.")

	context = ssl.create_default_context()
	try:
		if config["security"] == "implicit-tls":
			client = smtplib.SMTP_SSL(config["host"], config["port"], timeout=timeout, context=context)
		else:
			client = smtplib.SMTP(config["host"], config["port"], timeout=timeout)

		with client:
			client.ehlo_or_helo_if_needed()
			if config["security"] == "starttls":
				if not client.has_extn("starttls"):
					raise RelayConfigurationError("The SMTP relay does not advertise STARTTLS.")
				client.starttls(context=context)
				client.ehlo()
			client.login(config["username"], password)
			client.noop()
	except RelayConfigurationError:
		raise
	except smtplib.SMTPAuthenticationError as exc:
		raise RelayConfigurationError("The SMTP relay rejected the username or password.") from exc
	except ssl.SSLCertVerificationError as exc:
		raise RelayConfigurationError("The SMTP relay TLS certificate could not be verified: {}".format(exc.verify_message)) from exc
	except smtplib.SMTPException as exc:
		raise RelayConfigurationError("The SMTP relay rejected the connection or SMTP login.") from exc
	except (socket.gaierror, socket.timeout, TimeoutError, ConnectionError, OSError) as exc:
		raise RelayConfigurationError("Could not connect to and authenticate with the SMTP relay: {}".format(exc)) from exc

	return "SMTP relay connection, TLS, and authentication succeeded at {}.".format(relay_destination(config))


def config_from_args(args):
	return {
		"enabled": True,
		"host": args.host,
		"port": args.port,
		"security": args.security,
		"username": args.username,
	}


def main():
	parser = argparse.ArgumentParser(description="Validate or test authenticated SMTP relay settings.")
	parser.add_argument("command", choices=("validate", "normalize", "has-credentials", "check"))
	parser.add_argument("--host", required=True)
	parser.add_argument("--port", required=True)
	parser.add_argument("--security", required=True, choices=sorted(VALID_SECURITY))
	parser.add_argument("--username", required=True)
	parser.add_argument("--password-stdin", action="store_true")
	args = parser.parse_args()
	config = config_from_args(args)

	try:
		validate_smtp_relay_config(config)
		if args.command == "validate":
			return 0
		if args.command == "normalize":
			print("{}\t{}".format(
				config["host"].encode("idna").decode("ascii").lower(),
				int(config["port"])))
			return 0
		if args.command == "has-credentials":
			load_smtp_relay_password(config)
			return 0
		password = sys.stdin.readline().rstrip("\r\n") if args.password_stdin else None
		print(check_smtp_relay(config, password=password))
		return 0
	except RelayConfigurationError as exc:
		print(str(exc), file=sys.stderr)
		return 1


if __name__ == "__main__":
	sys.exit(main())
