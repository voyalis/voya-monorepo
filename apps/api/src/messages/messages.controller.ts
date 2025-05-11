// voya-monorepo/apps/api/src/messages/messages.controller.ts
import { Controller, Get, Post, Body, ValidationPipe } from '@nestjs/common';
import { MessagesService, CreateMessageDto } from './messages.service';
import { Message } from './message.entity';

@Controller('messages') // Bu controller /messages path'i ile eşleşecek
export class MessagesController {
  constructor(private readonly messagesService: MessagesService) {}

  @Post() // POST /messages
  async create(
    @Body(new ValidationPipe()) createMessageDto: CreateMessageDto,
  ): Promise<Message> {
    // @Body() ile request body'sindeki JSON'u alırız
    // ValidationPipe eklenebilir (class-validator, class-transformer paketleri gerekir)
    return this.messagesService.create(createMessageDto);
  }

  @Get() // GET /messages
  async findAll(): Promise<Message[]> {
    return this.messagesService.findAll();
  }
}
