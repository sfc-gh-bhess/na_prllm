FROM python:3.11

WORKDIR /app
ADD ./requirements.txt /app/

RUN pip install --no-cache-dir -r requirements.txt

ADD ./ /app

EXPOSE 5000

ENV FLASK_APP=app
CMD ["fastapi", "run", "app.py", "--port", "5000"]
