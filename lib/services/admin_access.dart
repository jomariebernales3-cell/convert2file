class AdminAccess {
  static const email = 'admin@convert2file.app';

  static bool isAdministratorEmail(String value) =>
      value.trim().toLowerCase() == email;
}
