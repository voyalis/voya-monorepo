import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { ConfigService } from '@nestjs/config';
import { ValidationPipe } from '@nestjs/common'; // ValidationPipe için import

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  const configService = app.get(ConfigService);
  const port = configService.get<number>('PORT') || 3000;

  app.setGlobalPrefix('api/v1'); // <-- YENİ EKLENEN SATIR

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

  await app.listen(port);
  console.log(`Application is running on: ${await app.getUrl()}`);
}
bootstrap();
