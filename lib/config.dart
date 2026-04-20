class AppConfig {
  // Меняй в зависимости от того где запускаешь
  //static const _host = 'localhost';       // Windows
  //static const _host = '10.0.2.2';    // Android эмулятор
  static const _host = '10.37.44.41';

  static const _port = '8080';

  static String get apiUrl => 'http://$_host:$_port';
  static String get wsUrl  => 'ws://$_host:$_port/ws';
}