#!/usr/bin/env python3

import os
import sys
import tempfile
import unittest
from unittest import mock


sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "management"))

import smtp_relay


class SMTPRelayConfigurationTests(unittest.TestCase):
	def setUp(self):
		self.config = {
			"enabled": True,
			"host": "smtp.provider.example",
			"port": "587",
			"security": "starttls",
			"username": "account@example.com",
		}

	def test_relay_is_disabled_by_default(self):
		self.assertFalse(smtp_relay.smtp_relay_enabled({}))
		self.assertTrue(smtp_relay.smtp_relay_enabled({"ENABLE_SMTP_RELAY": "1"}))
		self.assertTrue(smtp_relay.should_generate_direct_delivery_spf({}))
		self.assertFalse(smtp_relay.should_generate_direct_delivery_spf({"ENABLE_SMTP_RELAY": "1"}))

	def test_config_is_normalized(self):
		config = smtp_relay.get_smtp_relay_config({
			"ENABLE_SMTP_RELAY": "1",
			"SMTP_RELAY_HOST": self.config["host"],
			"SMTP_RELAY_PORT": self.config["port"],
			"SMTP_RELAY_SECURITY": self.config["security"],
			"SMTP_RELAY_USERNAME": self.config["username"],
		})
		self.assertEqual(config["port"], 587)
		self.assertEqual(smtp_relay.relay_destination(config), "[smtp.provider.example]:587")

	def test_invalid_config_is_rejected(self):
		invalid_values = (
			("host", "localhost"),
			("host", "bad_host.example"),
			("port", "0"),
			("port", "not-a-port"),
			("security", "none"),
			("username", "bad username"),
			("username", "$(bad)"),
		)
		for field, value in invalid_values:
			with self.subTest(field=field, value=value):
				config = dict(self.config)
				config[field] = value
				with self.assertRaises(smtp_relay.RelayConfigurationError):
					smtp_relay.validate_smtp_relay_config(config)

	def test_password_map_uses_exact_destination_and_preserves_colons(self):
		with tempfile.NamedTemporaryFile("w", encoding="utf-8") as password_map:
			password_map.write("[other.example]:587 account@example.com:wrong\n")
			password_map.write("[smtp.provider.example]:587 account@example.com:correct:with:colons\n")
			password_map.flush()
			password = smtp_relay.load_smtp_relay_password(self.config, password_map.name)
		self.assertEqual(password, "correct:with:colons")


class SMTPRelayConnectionTests(unittest.TestCase):
	def setUp(self):
		self.config = {
			"enabled": True,
			"host": "smtp.provider.example",
			"port": 587,
			"security": "starttls",
			"username": "account@example.com",
		}

	@mock.patch("smtp_relay.ssl.create_default_context")
	@mock.patch("smtp_relay.smtplib.SMTP")
	def test_starttls_connection_authenticates_without_sending_mail(self, smtp_class, create_context):
		client = smtp_class.return_value
		client.has_extn.return_value = True
		message = smtp_relay.check_smtp_relay(self.config, password="secret")

		smtp_class.assert_called_once_with("smtp.provider.example", 587, timeout=10)
		client.starttls.assert_called_once_with(context=create_context.return_value)
		client.login.assert_called_once_with("account@example.com", "secret")
		client.noop.assert_called_once_with()
		self.assertFalse(hasattr(client, "sendmail") and client.sendmail.called)
		self.assertIn("authentication succeeded", message)

	@mock.patch("smtp_relay.ssl.create_default_context")
	@mock.patch("smtp_relay.smtplib.SMTP_SSL")
	def test_implicit_tls_connection_authenticates(self, smtp_ssl_class, create_context):
		config = dict(self.config, port=465, security="implicit-tls")
		client = smtp_ssl_class.return_value
		smtp_relay.check_smtp_relay(config, password="secret")

		smtp_ssl_class.assert_called_once_with(
			"smtp.provider.example", 465, timeout=10, context=create_context.return_value)
		client.starttls.assert_not_called()
		client.login.assert_called_once_with("account@example.com", "secret")

	@mock.patch("smtp_relay.ssl.create_default_context")
	@mock.patch("smtp_relay.smtplib.SMTP")
	def test_authentication_failure_does_not_expose_provider_response(self, smtp_class, _create_context):
		client = smtp_class.return_value
		client.has_extn.return_value = True
		client.login.side_effect = smtp_relay.smtplib.SMTPAuthenticationError(535, b"secret rejected")
		with self.assertRaisesRegex(smtp_relay.RelayConfigurationError, "rejected the username or password") as error:
			smtp_relay.check_smtp_relay(self.config, password="secret")
		self.assertNotIn("secret", str(error.exception))


if __name__ == "__main__":
	unittest.main()
