import 'package:flutter_test/flutter_test.dart';
import 'package:mtools/core/utils/connection_target.dart';

void main() {
  group('classifyHost — özel ağ (RFC1918)', () {
    test('10.0.0.0/8', () {
      expect(classifyHost('10.0.0.1'), ConnectionTarget.privateNetwork);
      expect(classifyHost('10.255.255.255'), ConnectionTarget.privateNetwork);
    });

    test('172.16.0.0/12 sınırları', () {
      expect(classifyHost('172.16.0.1'), ConnectionTarget.privateNetwork);
      expect(classifyHost('172.31.255.255'), ConnectionTarget.privateNetwork);
      expect(classifyHost('172.15.0.1'), ConnectionTarget.external);
      expect(classifyHost('172.32.0.1'), ConnectionTarget.external);
    });

    test('192.168.0.0/16', () {
      expect(classifyHost('192.168.1.10'), ConnectionTarget.privateNetwork);
      expect(classifyHost('192.168.255.255'), ConnectionTarget.privateNetwork);
      expect(classifyHost('192.169.1.10'), ConnectionTarget.external);
    });
  });

  group('classifyHost — Tailscale (100.64.0.0/10)', () {
    test('aralık içi', () {
      expect(classifyHost('100.64.0.1'), ConnectionTarget.tailscale);
      expect(classifyHost('100.100.50.1'), ConnectionTarget.tailscale);
      expect(classifyHost('100.127.255.255'), ConnectionTarget.tailscale);
    });

    test('aralık sınırları', () {
      expect(classifyHost('100.63.255.255'), ConnectionTarget.external);
      expect(classifyHost('100.128.0.1'), ConnectionTarget.external);
    });
  });

  group('classifyHost — dış', () {
    test('herkese açık IP', () {
      expect(classifyHost('1.1.1.1'), ConnectionTarget.external);
      expect(classifyHost('8.8.8.8'), ConnectionTarget.external);
    });

    test('hostname (DNS çözümlemeye girmez)', () {
      expect(classifyHost('proxmox.example.com'), ConnectionTarget.external);
      expect(classifyHost('myserver.local'), ConnectionTarget.external);
    });

    test('IPv6 kapsam dışı — external sayılır', () {
      expect(classifyHost('::1'), ConnectionTarget.external);
      expect(classifyHost('fd7a:115c:a1e0::1'), ConnectionTarget.external);
    });
  });

  group('classifyHost — girdi biçimleri', () {
    test('port ile bare IP', () {
      expect(classifyHost('192.168.1.10:8006'), ConnectionTarget.privateNetwork);
      expect(classifyHost('100.64.1.5:3000'), ConnectionTarget.tailscale);
    });

    test('şemalı URL', () {
      expect(classifyHost('https://192.168.1.10:8006'),
          ConnectionTarget.privateNetwork);
      expect(classifyHost('http://100.64.1.5:3000'), ConnectionTarget.tailscale);
      expect(
          classifyHost('https://proxmox.example.com'), ConnectionTarget.external);
    });

    test('boş girdi', () {
      expect(classifyHost(''), ConnectionTarget.external);
    });
  });
}
