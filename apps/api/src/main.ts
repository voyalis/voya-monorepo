import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { ConfigService } from '@nestjs/config';
import { ValidationPipe } from '@nestjs/common'; // ValidationPipe için import

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  const configService = app.get(ConfigService); // ConfigService'i AppModule'den alıyoruz
  const port = configService.get<number>('PORT') || 3000;

  app.setGlobalPrefix('api/v1'); // Global API ön ekimiz

  // Global ValidationPipe'ı da burada tanımlayabiliriz,
  // böylece her controller'da @UsePipes dememize gerek kalmaz.
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true, // DTO'da olmayan alanları at
      forbidNonWhitelisted: true, // DTO'da olmayan alan gelirse hata ver
      transform: true, // Gelen veriyi DTO tipine dönüştür
      transformOptions: {
        enableImplicitConversion: true, // String'den number'a vb. otomatik dönüşüm
      },
    }),
  );

  // Uygulamanın tüm arayüzlerden gelen istekleri dinlemesini sağlıyoruz.
  await app.listen(port, '0.0.0.0'); // <-- '0.0.0.0' EKLENDİ/KONTROL EDİLDİ!
  console.log(
    `Application is running on: http://0.0.0.0:${port} (publicly via Fly.io on port 80/443)`,
  );
  console.log(`Local access (if forwarded): http://localhost:${port}`);
}
bootstrap();
