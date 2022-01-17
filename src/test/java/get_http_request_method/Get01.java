package get_http_request_method;

import base_urls.HerokuappBaseUrl;
import io.restassured.builder.RequestSpecBuilder;
import io.restassured.http.ContentType;
import io.restassured.response.Response;
import io.restassured.specification.RequestSpecification;
import org.junit.Test;

import static io.restassured.RestAssured.given;

public class Get01 extends HerokuappBaseUrl {



    //Gherkin key words

    //given   => baslangic islemini temsil eder. pre-requisite
    //WHen    => islemin action kismini tanimlar
    //AND     => tekrar eden islemleri gosterir
    //Then    => islemin sonunu ve validation u gosterir



       /*
    Given
           https://restful-booker.herokuapp.com/booking/3

    When
         user sends a request to the url

    Then
         HTTP Status code should be 200


     And
         ContentType should be JSON

     And
        Status Line should be HTTP/1.1 200 OK

     */



    @Test
    public void get01(){

        String endpoint = "https://restful-booker.herokuapp.com/booking/3";
        //organize bir yol degil

        Response response = given().when().get(endpoint);

        response.prettyPrint();

    }





       /*
    Given
           https://restful-booker.herokuapp.com/booking/3

    When
         user sends a request to the url

    Then
         HTTP Status code should be 200


     And
         ContentType should be JSON

     And
        Status Line should be HTTP/1.1 200 OK

     */

    @Test
    public void test(){




        //Set the url / urli set et
        spec.pathParams("bir", "booking","iki", 2);


        //   /{bir}/{iki}
        //Get request yap ve Response al
        Response response = given().spec(spec).when().get("/{bir}/{iki}");

        response.prettyPrint();


        //validation


        response.then().assertThat().statusCode(200).contentType(ContentType.JSON).statusLine("HTTP/1.1 200 OK");



    }



}
