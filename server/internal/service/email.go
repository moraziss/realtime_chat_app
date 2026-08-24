package service

import (
	"fmt"
	"net/smtp"
	"os"
)

// Sender - интерфейс для отправки писем
type EmailSender interface {
	SendVerificationCode(toEmail, code string) error
}

type gmailSender struct {
	host     string
	port     string
	user     string
	password string
}

func NewEmailSender() EmailSender {
	// Проверяем оба варианта названия переменной для надежности
	password := os.Getenv("SMTP_PASS")
	if password == "" {
		password = os.Getenv("SMTP_PASSWORD")
	}

	return &gmailSender{
		host:     os.Getenv("SMTP_HOST"),
		port:     os.Getenv("SMTP_PORT"),
		user:     os.Getenv("SMTP_USER"),
		password: password,
	}
}

func (s *gmailSender) SendVerificationCode(toEmail, code string) error {
	if s.user == "" || s.password == "" {
		return fmt.Errorf("SMTP credentials are not configured")
	}

	subject := "Подтверждение регистрации в мессенджере!"
	
	// Правильное формирование заголовков письма
	header := make(map[string]string)
	header["From"] = s.user
	header["To"] = toEmail
	header["Subject"] = subject
	header["MIME-Version"] = "1.0"
	header["Content-Type"] = "text/html; charset=\"UTF-8\""

	message := ""
	for k, v := range header {
		message += fmt.Sprintf("%s: %s\r\n", k, v)
	}

	body := fmt.Sprintf(`
		<html>
		<body style="font-family: Arial, sans-serif;">
			<h2>Добро пожаловать!</h2>
			<p>Твой код для подтверждения регистрации:</p>
			<h1 style="color: #4CAF50; letter-spacing: 5px; font-size: 32px;">%s</h1>
			<p>Если ты не запрашивал этот код, просто проигнорируй это письмо.</p>
		</body>
		</html>
	`, code)

	msg := []byte(message + "\r\n" + body)
	
	auth := smtp.PlainAuth("", s.user, s.password, s.host)
	addr := fmt.Sprintf("%s:%s", s.host, s.port)
	
	err := smtp.SendMail(addr, auth, s.user, []string{toEmail}, msg)
	if err != nil {
		return fmt.Errorf("ошибка отправки письма: %v", err)
	}

	return nil
}
