FROM ruby:latest
COPY . .
RUN bundle install
ENTRYPOINT [ "bundle", "exec", "rsmp" ]
CMD [ "site", "-s", "host.docker.internal:12111" ]
