// voya-monorepo/apps/api/src/messages/messages.module.ts
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { MessagesService } from './messages.service';
import { MessagesController } from './messages.controller';
import { Message } from './message.entity'; // Oluşturduğumuz entity'yi import et

@Module({
  imports: [
    TypeOrmModule.forFeature([Message]), // Message entity'sini bu modül için tanıt
  ],
  controllers: [MessagesController],
  providers: [MessagesService],
})
export class MessagesModule {}
