FROM python:3.12-slim

RUN pip install flask
RUN pip install requests
RUN pip install mysql-connector-python
COPY --chmod=755 app.py /app.py
CMD [ "/app.py" ]
