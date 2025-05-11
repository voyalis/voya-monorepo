import { Module } from '@nestjs/common';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { TypeOrmModule } from '@nestjs/typeorm';
import { ConfigModule, ConfigService } from '@nestjs/config'; // Tekrar aktif ettik
import { Message } from './messages/message.entity'; // Message entity'miz

// MessagesModule'ü hala yorumlu/silinmiş tutuyoruz
// import { MessagesModule } from './messages/messages.module';

@Module({
  imports: [
    ConfigModule.forRoot({
      // Tekrar aktif ettik
      isGlobal: true,
      envFilePath: '.env',
    }),
    TypeOrmModule.forRootAsync({
      // forRootAsync'e geri döndük
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (configService: ConfigService) => ({
        type: 'postgres',
        host: configService.get<string>('DATABASE_HOST'),
        port: parseInt(configService.get<string>('DATABASE_PORT') || '5433'),
        username: configService.get<string>('DATABASE_USER'),
        password: configService.get<string>('DATABASE_PASSWORD'),
        database: configService.get<string>('DATABASE_DB_NAME'),
        entities: [Message], // DİKKAT: Burası direkt [Message] olarak kalacak! Glob deseni yok.
        synchronize: true,
        logging: true,
      }),
    }),
    // MessagesModule,
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
